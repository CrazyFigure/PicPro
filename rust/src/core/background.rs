//! 背景识别与换色。
//!
//! 纯算法实现（无机器学习模型），针对**均匀背景**的证件照、产品图。
//! 完整流程分五步，每一步都解决一个具体问题：
//!
//! 1. **背景建模**：只采样上边与左右两侧上方区域，并对样本做离群剔除。
//!    不能采样下边缘——人像照的肩部常压住下边缘，混入会污染背景估计。
//! 2. **连通域抠图**：从图像边界向内做洪水填充，而不是单纯按颜色阈值判断。
//!    这是本算法的关键：白衬衫与白背景颜色几乎相同，仅靠颜色会把衬衫挖空；
//!    而衬衫被深色西装包围、不与画面边界连通，因此不会被填充到。
//! 3. **边缘收放**：对背景掩膜做**几何**膨胀/腐蚀，把前景边界整体平移若干像素。
//!    正值膨胀背景即收缩前景（可去掉一圈背景残留与白边），负值反之。
//! 4. **软边过渡**：对紧邻背景边界的一圈像素按颜色距离给出 0~1 的 alpha，
//!    而不是硬边，让发丝有自然的半透明过渡。过渡带的**几何宽度**由
//!    `feather_px` 决定，带内 alpha 的**颜色判据**由 `tolerance` 决定——
//!    两者解耦，因此界面上两个参数各自都能产生明确、可预期的效果。
//! 5. **白底去污染**：半透明像素里混有原背景色，直接合成会在新底色上留下
//!    发白的轮廓。利用 `I = a·F + (1-a)·Bg` 反解出前景真实颜色
//!    `F = (I - (1-a)·Bg) / a`，从根本上消除白边。
//! 6. **合成**：`out = a·F + (1-a)·目标色`。
//!
//! 能力边界：背景若本身存在强渐变或复杂纹理，全局颜色模型会失效，
//! 此时应改用云端 AI 抠图（内核已预留接口）。这一限制在界面上需要明确提示。

use std::collections::VecDeque;

use image::{Rgba, RgbaImage};

use crate::core::error::{PicProError, Result};
use crate::core::types::{Frame, RasterImage};

/// 换背景参数。
#[derive(Debug, Clone)]
pub struct BackgroundOptions {
    /// 目标底色 RGB
    pub target_color: [u8; 3],
    /// 背景相似度阈值（0~1）。越大越宽松，越容易把接近背景的前景也判为背景。
    ///
    /// 该值同时决定两件事：洪水填充的硬阈值，以及软边过渡带内
    /// 「多接近才算背景」的颜色判据。取值越大，边缘处越多的半透明像素
    /// 会被归为背景，观感上是把轮廓向内收了一圈。
    pub tolerance: f32,
    /// 软边过渡带的**几何宽度**（像素）。只影响边界外侧多宽的一圈参与柔化，
    /// 不影响带内像素被判为前景还是背景（那由 `tolerance` 决定）。
    pub feather_px: u32,
    /// 是否做白底去污染。原背景非纯色时该修正可能失效，可关闭。
    pub decontaminate: bool,
    /// 边缘收放，取值 -1.0~1.0，作用在**几何**层面。
    /// 正值收缩前景（把前景边界向内平移，可去掉一圈背景残留与白边）；
    /// 负值扩张前景（把边界向外平移，保住更多发丝）。
    /// 平移量 = |edge_offset| × [`EDGE_MAX_PX`] 像素。
    pub edge_offset: f32,
    /// 是否对 alpha 做一次轻度平滑，抑制锯齿。
    pub smooth_alpha: bool,
    /// 是否保留原图 alpha（原图本就有透明区域时，与其相乘而不是覆盖）
    pub preserve_original_alpha: bool,
}

/// 「边缘收放」在滑杆极值处对应的几何平移量（像素）。
///
/// 用**绝对像素**而非图像尺寸的比例，是因为证件照在换背景之前
/// 已按规格裁到规定像素（如 295×413），此时绝对像素有明确含义；
/// 且预览与成品走同一条流水线、在相同像素尺度上处理，观感一致。
const EDGE_MAX_PX: f32 = 6.0;

/// 软边过渡带内颜色判据的固定色阶跨度。
///
/// 这里刻意**不**把上界设成阈值的倍数：那样阈值上移会同时抬高上下界，
/// 净效果互相抵消，界面上的「判定阈值」滑杆几乎看不出变化。
/// 固定跨度后，阈值上移会让中间地带的像素真正从前景翻转为背景。
const TOLERANCE_SPAN: f32 = 40.0;

impl Default for BackgroundOptions {
    fn default() -> Self {
        Self {
            target_color: [67, 142, 219], // 默认标准蓝底 #438EDB
            tolerance: 0.12,
            feather_px: 2,
            decontaminate: true,
            edge_offset: 0.0,
            smooth_alpha: true,
            preserve_original_alpha: true,
        }
    }
}

impl BackgroundOptions {
    /// 把**以像素为单位**的参数按给定比例缩放，其余参数原样保留。
    ///
    /// 用途：预览会先把图像降到较小尺寸再抠图（否则 12MP 照片单次预览要一秒以上，
    /// 界面会被冻住）。此时若不按同一比例缩放 `feather_px` 与 `edge_offset`，
    /// 预览里的边缘会比成品明显更硬或更软，「所见即所得」就不成立了。
    ///
    /// `tolerance` 是颜色维度、无色阶宽度，因此不参与缩放。
    pub fn scaled_to(&self, scale: f32) -> Self {
        let s = scale.clamp(0.0, 1.0);
        Self {
            feather_px: ((self.feather_px as f32) * s).round() as u32,
            edge_offset: self.edge_offset * s,
            ..self.clone()
        }
    }
}/// 背景颜色模型。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BackgroundModel {
    /// 估计出的背景色
    pub color: [f32; 3],
    /// 各通道样本标准差的最大值，用于自适应放宽阈值
    pub noise: f32,
    /// 参与建模的样本数，样本过少说明估计不可靠
    pub sample_count: usize,
}

/// 换背景的执行报告，便于界面提示用户算法是否可靠。
#[derive(Debug, Clone, Copy)]
pub struct BackgroundReport {
    pub model: BackgroundModel,
    /// 被判为背景的像素占比
    pub background_ratio: f32,
    /// 处于半透明过渡的像素占比
    pub feathered_ratio: f32,
}

/// 结果 + 报告。
pub struct BackgroundOutput {
    pub image: RasterImage,
    pub report: BackgroundReport,
}

/// 估计背景颜色模型。
///
/// 采样策略（有意避开下边缘）：
/// - 上边缘整行；
/// - 左右两列的上方 60%。
///
/// 估计步骤：先取各通道中位数作为初值，再剔除偏离初值过大的样本后求均值，
/// 这样即使边缘混入了少量前景像素（如发梢、衣领）也不会显著影响结果。
pub fn estimate_background(img: &RgbaImage) -> Result<BackgroundModel> {
    let (w, h) = (img.width(), img.height());
    if w == 0 || h == 0 {
        return Err(PicProError::InvalidArgument("图像尺寸为空".into()));
    }

    let mut samples: Vec<[f32; 3]> = Vec::new();
    // 左右列只取上方 60%：下方通常是肩部与手臂
    let col_limit = ((h as f32) * 0.6).ceil() as u32;
    // 上边缘：逐列采样（宽图时抽稀以控制样本量）
    let step = (w / 256).max(1);
    for x in (0..w).step_by(step as usize) {
        let p = img.get_pixel(x, 0).0;
        samples.push([p[0] as f32, p[1] as f32, p[2] as f32]);
    }
    for y in (0..col_limit).step_by(step as usize) {
        let l = img.get_pixel(0, y).0;
        let r = img.get_pixel(w - 1, y).0;
        samples.push([l[0] as f32, l[1] as f32, l[2] as f32]);
        samples.push([r[0] as f32, r[1] as f32, r[2] as f32]);
    }

    if samples.is_empty() {
        return Err(PicProError::InvalidArgument("无法采样到背景像素".into()));
    }

    // 逐通道中位数作为初值
    let mut median = [0f32; 3];
    for c in 0..3usize {
        let mut vals: Vec<f32> = samples.iter().map(|s| s[c]).collect();
        vals.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
        median[c] = vals[vals.len() / 2];
    }

    // 剔除离群样本后求均值与标准差
    let mut sum = [0f64; 3];
    let mut sum_sq = [0f64; 3];
    let mut count = 0usize;
    for s in &samples {
        let dev = (0..3usize)
            .map(|c| (s[c] - median[c]).abs())
            .fold(0.0f32, f32::max);
        // 偏离中位数超过 48 个色阶的样本视为前景，剔除
        if dev > 48.0 {
            continue;
        }
        count += 1;
        for c in 0..3usize {
            sum[c] += s[c] as f64;
            sum_sq[c] += (s[c] as f64) * (s[c] as f64);
        }
    }

    // 剔除后样本过少则退回中位数估计，避免均值不可靠
    if count < 8 {
        return Ok(BackgroundModel {
            color: median,
            noise: 0.0,
            sample_count: samples.len(),
        });
    }

    let mut color = [0f32; 3];
    let mut max_std = 0f32;
    for c in 0..3usize {
        let mean = sum[c] / count as f64;
        color[c] = mean as f32;
        let var = (sum_sq[c] / count as f64) - mean * mean;
        let std = if var > 0.0 { (var as f32).sqrt() } else { 0.0 };
        if std > max_std {
            max_std = std;
        }
    }

    Ok(BackgroundModel {
        color,
        noise: max_std,
        sample_count: count,
    })
}

/// 计算每个像素与背景色的差异（0~255，取通道最大差值）。
///
/// 用切比雪夫距离而非欧氏距离：背景近似单色时它对「单通道偏移」
/// 更敏感，比欧氏距离更能把轻微偏色的背景像素识别出来。
fn compute_diff(img: &RgbaImage, model: &BackgroundModel) -> Vec<u8> {
    let n = (img.width() * img.height()) as usize;
    let mut diff = vec![0u8; n];
    let [br, bg, bb] = model.color;
    for (i, px) in img.pixels().enumerate() {
        let p = px.0;
        let d0 = (p[0] as f32 - br).abs();
        let d1 = (p[1] as f32 - bg).abs();
        let d2 = (p[2] as f32 - bb).abs();
        let d = d0.max(d1).max(d2);
        // 归一到 0~255 的整数，节省内存
        diff[i] = d.min(255.0).round() as u8;
    }
    diff
}

/// 从图像边界向内做洪水填充，得到硬背景掩膜。
///
/// 采用 **4 邻域**而不是 8 邻域：8 邻域会沿对角缝隙渗入发丝内部，
/// 导致发丝被过度侵蚀；4 邻域更保守，能保住细结构。
fn flood_fill_background(diff: &[u8], w: u32, h: u32, threshold: u8) -> Vec<bool> {
    let n = (w * h) as usize;
    let mut mask = vec![false; n];
    let mut queue: VecDeque<u32> = VecDeque::new();

    // 种子：四条边上所有满足阈值的像素
    let push = |idx: u32, mask: &mut Vec<bool>, queue: &mut VecDeque<u32>| {
        if !mask[idx as usize] && diff[idx as usize] <= threshold {
            mask[idx as usize] = true;
            queue.push_back(idx);
        }
    };

    for x in 0..w {
        push(x, &mut mask, &mut queue); // 上边
        push((h - 1) * w + x, &mut mask, &mut queue); // 下边
    }
    for y in 0..h {
        push(y * w, &mut mask, &mut queue); // 左边
        push(y * w + w - 1, &mut mask, &mut queue); // 右边
    }

    // 广度优先扩散
    while let Some(idx) = queue.pop_front() {
        let x = idx % w;
        let y = idx / w;
        // 左
        if x > 0 {
            let ni = idx - 1;
            if !mask[ni as usize] && diff[ni as usize] <= threshold {
                mask[ni as usize] = true;
                queue.push_back(ni);
            }
        }
        // 右
        if x + 1 < w {
            let ni = idx + 1;
            if !mask[ni as usize] && diff[ni as usize] <= threshold {
                mask[ni as usize] = true;
                queue.push_back(ni);
            }
        }
        // 上
        if y > 0 {
            let ni = idx - w;
            if !mask[ni as usize] && diff[ni as usize] <= threshold {
                mask[ni as usize] = true;
                queue.push_back(ni);
            }
        }
        // 下
        if y + 1 < h {
            let ni = idx + w;
            if !mask[ni as usize] && diff[ni as usize] <= threshold {
                mask[ni as usize] = true;
                queue.push_back(ni);
            }
        }
    }

    mask
}

/// 对前景掩膜做膨胀（可分离，先横向再纵向）。
fn dilate(mask: &[bool], w: u32, h: u32, radius: u32) -> Vec<bool> {
    if radius == 0 {
        return mask.to_vec();
    }
    let r = radius as i32;
    let mut tmp = vec![false; mask.len()];
    // 横向膨胀
    for y in 0..h {
        for x in 0..w {
            let mut hit = false;
            let x0 = (x as i32 - r).max(0);
            let x1 = (x as i32 + r).min(w as i32 - 1);
            for xx in x0..=x1 {
                if mask[(y * w + xx as u32) as usize] {
                    hit = true;
                    break;
                }
            }
            tmp[(y * w + x) as usize] = hit;
        }
    }
    // 纵向膨胀
    let mut out = vec![false; mask.len()];
    for y in 0..h {
        let y0 = (y as i32 - r).max(0);
        let y1 = (y as i32 + r).min(h as i32 - 1);
        for x in 0..w {
            let mut hit = false;
            for yy in y0..=y1 {
                if tmp[(yy as u32 * w + x) as usize] {
                    hit = true;
                    break;
                }
            }
            out[(y * w + x) as usize] = hit;
        }
    }
    out
}

/// 对背景掩膜做腐蚀（可分离）。
///
/// 腐蚀用于「扩张前景」：把背景判定收缩若干像素，让边界向外让出空间。
/// 实现上复用 [`dilate`]——对补集膨胀再取反，数学上等价于腐蚀，
/// 避免再维护一份对称的循环代码。
fn erode(mask: &[bool], w: u32, h: u32, radius: u32) -> Vec<bool> {
    if radius == 0 {
        return mask.to_vec();
    }
    let inverted: Vec<bool> = mask.iter().map(|v| !v).collect();
    let grown = dilate(&inverted, w, h, radius);
    grown.into_iter().map(|v| !v).collect()
}

/// 对 alpha 做 3x3 均值平滑（仅在过渡带内），抑制锯齿。
fn smooth_alpha_band(alpha: &mut [f32], band: &[bool], w: u32, h: u32) {
    let src = alpha.to_vec();
    for y in 1..h.saturating_sub(1) {
        for x in 1..w.saturating_sub(1) {
            let i = (y * w + x) as usize;
            if !band[i] {
                continue;
            }
            let mut sum = 0.0;
            for dy in 0..3u32 {
                for dx in 0..3u32 {
                    sum += src[(((y - 1 + dy) * w) + (x - 1 + dx)) as usize];
                }
            }
            alpha[i] = sum / 9.0;
        }
    }
}

/// 执行换背景。
///
/// 动画图会用**第一帧**估计背景模型，随后逐帧独立抠图合成：
/// 这样即使主体有位移也能正确抠出，同时保持背景色一致。
pub fn replace_background(img: &RasterImage, opts: &BackgroundOptions) -> Result<BackgroundOutput> {
    if img.frames.is_empty() {
        return Err(PicProError::InvalidArgument("图像不含任何帧".into()));
    }
    // 参数边界保护：阈值与羽化范围越界会让结果完全失真
    if !(0.0..=1.0).contains(&opts.tolerance) {
        return Err(PicProError::InvalidArgument(format!(
            "背景阈值应在 0~1 之间，当前 {}",
            opts.tolerance
        )));
    }
    if !(-1.0..=1.0).contains(&opts.edge_offset) {
        return Err(PicProError::InvalidArgument(format!(
            "边缘收放应在 -1~1 之间，当前 {}",
            opts.edge_offset
        )));
    }

    // 用第一帧估计背景模型
    let model = estimate_background(&img.frames[0].pixels)?;
    // 硬阈值：背景本身有噪声时适当放宽，否则固定阈值可能把背景判成前景。
    // 该阈值同时是洪水填充的判据与软边过渡带的下界，
    // 因此界面上的「判定阈值」直接决定了「多接近背景算背景」。
    let tol_px = (opts.tolerance * 255.0).max(model.noise * 4.0).clamp(4.0, 200.0);
    // 过渡带上界：固定跨度而非按比例放大，避免阈值上移时上下界同步抬高、
    // 净效果互相抵消（旧实现的问题，表现为滑杆调节几乎无效）。
    let tol_hi = (tol_px + TOLERANCE_SPAN).min(255.0);
    // 「边缘收放」对应的几何平移量
    let edge_r = (opts.edge_offset.abs() * EDGE_MAX_PX).round() as u32;

    let w = img.width;
    let h = img.height;

    let mut frames = Vec::with_capacity(img.frames.len());
    let mut last_bg_ratio = 0.0f32;
    let mut last_feather_ratio = 0.0f32;

    for f in &img.frames {
        let diff = compute_diff(&f.pixels, &model);
        let strict = tol_px.round() as u8;
        let bg_orig = flood_fill_background(&diff, w, h, strict);

        // 边缘收放（几何）：正值收缩前景 => 膨胀背景掩膜；负值扩张前景 => 腐蚀背景掩膜。
        let bg_mask = if edge_r == 0 {
            bg_orig.clone()
        } else if opts.edge_offset > 0.0 {
            dilate(&bg_orig, w, h, edge_r)
        } else {
            erode(&bg_orig, w, h, edge_r)
        };

        // 过渡带 = 背景掩膜外扩 feather 后减去其自身
        let dilated = if opts.feather_px > 0 {
            dilate(&bg_mask, w, h, opts.feather_px)
        } else {
            bg_mask.clone()
        };

        // 计算 alpha：1 表示完全不透明的前景
        let n = (w * h) as usize;
        let mut alpha = vec![1.0f32; n];
        let mut bg_count = 0usize;
        let mut feather_count = 0usize;
        let mut band = vec![false; n];

        for i in 0..n {
            if bg_mask[i] {
                // 明确背景：完全透明
                alpha[i] = 0.0;
                bg_count += 1;
            } else if dilated[i] && !bg_orig[i] {
                // 过渡带：按颜色距离给出半透明值。
                // 条件里的 `!bg_orig[i]` 很关键——因「扩张前景」而从原背景
                // 收回的像素本身就接近背景色，若按颜色距离计算会被判成全透明，
                // 反而抵消掉扩张效果，因此这些像素一律按实心前景处理。
                band[i] = true;
                let d = diff[i] as f32;
                let a = ((d - tol_px) / (tol_hi - tol_px)).clamp(0.0, 1.0);
                alpha[i] = a;
                if a > 0.0 && a < 1.0 {
                    feather_count += 1;
                }
            }
            // 其余像素保持 alpha = 1（保护被前景包围的浅色区域，如白衬衫）
        }

        if opts.smooth_alpha {
            smooth_alpha_band(&mut alpha, &band, w, h);
        }

        // 合成
        let out = composite(&f.pixels, &alpha, &model, opts);

        // 释放掩膜，降低峰值内存
        band.clear();

        frames.push(Frame {
            pixels: out,
            delay_ms: f.delay_ms,
        });

        last_bg_ratio = bg_count as f32 / n as f32;
        last_feather_ratio = feather_count as f32 / n as f32;
    }

    let _ = &mut last_bg_ratio;

    Ok(BackgroundOutput {
        image: RasterImage::from_frames(w, h, frames),
        report: BackgroundReport {
            model,
            background_ratio: last_bg_ratio,
            feathered_ratio: last_feather_ratio,
        },
    })
}

/// 按 alpha 把前景合成到目标底色上，并做白底去污染。
///
/// 去污染公式：`F = (I - (1-a)·Bg) / a`，再 `out = a·F + (1-a)·Target`。
/// 该修正只在 `0 < a < 1` 的半透明像素上生效——完全不透明的像素本身
/// 已不含背景成分，强行修正只会引入误差。
fn composite(
    src: &RgbaImage,
    alpha: &[f32],
    model: &BackgroundModel,
    opts: &BackgroundOptions,
) -> RgbaImage {
    let (w, h) = (src.width(), src.height());
    let mut out = RgbaImage::new(w, h);
    let target = opts.target_color;
    let bgc = model.color;
    // alpha 下限：过小的 alpha 会让除法放大噪声，且这些像素视觉上已接近纯背景
    const ALPHA_EPS: f32 = 0.20;

    for (i, px) in src.pixels().enumerate() {
        let p = px.0;
        let mut a = alpha[i].clamp(0.0, 1.0);
        // 原图自带 alpha 时相乘保留，避免把原本透明的区域重新画实
        if opts.preserve_original_alpha {
            a *= p[3] as f32 / 255.0;
        }

        let out_rgb = if a <= 0.0 {
            // 完全背景 → 直接输出目标底色
            target
        } else if a >= 1.0 {
            // 完全前景 → 原色
            [p[0], p[1], p[2]]
        } else {
            // 半透明：先去污染还原前景真实颜色，再与目标底色混合
            let (fr, fg, fb) = if opts.decontaminate {
                let ae = a.max(ALPHA_EPS);
                let inv = 1.0 - ae;
                (
                    ((p[0] as f32 - inv * bgc[0]) / ae).clamp(0.0, 255.0),
                    ((p[1] as f32 - inv * bgc[1]) / ae).clamp(0.0, 255.0),
                    ((p[2] as f32 - inv * bgc[2]) / ae).clamp(0.0, 255.0),
                )
            } else {
                (p[0] as f32, p[1] as f32, p[2] as f32)
            };
            [
                (a * fr + (1.0 - a) * target[0] as f32).round().clamp(0.0, 255.0) as u8,
                (a * fg + (1.0 - a) * target[1] as f32).round().clamp(0.0, 255.0) as u8,
                (a * fb + (1.0 - a) * target[2] as f32).round().clamp(0.0, 255.0) as u8,
            ]
        };

        out.put_pixel(i as u32 % w, i as u32 / w, Rgba([out_rgb[0], out_rgb[1], out_rgb[2], 255]));
    }
    let _ = h;
    out
}

/// 便捷函数：把图换成指定纯色背景。
pub fn set_background_color(img: &RasterImage, color: [u8; 3]) -> Result<BackgroundOutput> {
    replace_background(
        img,
        &BackgroundOptions {
            target_color: color,
            ..Default::default()
        },
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 构造一张「白色背景 + 中央深色矩形」的测试图，
    /// 用于验证抠图不会把中央区域误判为背景。
    fn white_bg_with_center(w: u32, h: u32) -> RgbaImage {
        let mut img = RgbaImage::from_pixel(w, h, Rgba([255, 255, 255, 255]));
        for y in h / 4..h * 3 / 4 {
            for x in w / 4..w * 3 / 4 {
                img.put_pixel(x, y, Rgba([20, 20, 20, 255]));
            }
        }
        img
    }

    #[test]
    fn 背景估计出白色() {
        let img = white_bg_with_center(80, 80);
        let m = estimate_background(&img).unwrap();
        assert!(m.color[0] > 248.0 && m.color[1] > 248.0 && m.color[2] > 248.0);
        // 纯白背景噪声应极小
        assert!(m.noise < 2.0, "噪声应很小，实际 {}", m.noise);
    }

    #[test]
    fn 下边缘的主体会污染估计故不参与采样() {
        // 下边缘全部涂黑（模拟肩部压边），背景估计仍应为白色
        let mut img = white_bg_with_center(80, 80);
        for x in 0..80 {
            for y in 70..80 {
                img.put_pixel(x, y, Rgba([15, 15, 15, 255]));
            }
        }
        let m = estimate_background(&img).unwrap();
        assert!(
            m.color[0] > 240.0,
            "下边缘主体不应影响背景估计，实际 R={}",
            m.color[0]
        );
    }

    #[test]
    fn 换背景后背景变蓝且主体保留() {
        let img = white_bg_with_center(80, 80);
        let raster = RasterImage::from_image(img);
        let out = set_background_color(&raster, [67, 142, 219]).unwrap();

        let px = out.image.first();
        // 四角应变成蓝底
        assert_eq!(px.get_pixel(1, 1).0, [67, 142, 219, 255]);
        // 中央主体应保持深色
        let center = px.get_pixel(40, 40).0;
        assert!(center[0] < 40, "主体应保持深色，实际 {center:?}");
        // 背景占比应显著（此处约 75%）
        assert!(
            out.report.background_ratio > 0.6,
            "背景占比应较高，实际 {}",
            out.report.background_ratio
        );
    }

    #[test]
    fn 被前景包围的浅色区域不被挖空() {
        // 关键场景：白底上一个被深色环包围的白色区域（模拟白衬衫）
        // 该区域与画面边界不连通，必须保持不透明
        let mut img = RgbaImage::from_pixel(60, 60, Rgba([255, 255, 255, 255]));
        // 画一个深色环
        for y in 10..50 {
            for x in 10..50 {
                let on_ring = x < 14 || x >= 46 || y < 14 || y >= 46;
                if on_ring {
                    img.put_pixel(x, y, Rgba([30, 30, 30, 255]));
                }
            }
        }
        // 环内部保持白色（与背景同色，但被包围）
        let raster = RasterImage::from_image(img);
        let out = set_background_color(&raster, [67, 142, 219]).unwrap();

        let px = out.image.first();
        // 环内部应仍是白色，而不是被换成蓝色
        let inner = px.get_pixel(30, 30).0;
        assert_eq!(
            [inner[0], inner[1], inner[2]],
            [255, 255, 255],
            "被包围的白色区域不应被当作背景挖空，实际 {inner:?}"
        );
    }

    #[test]
    fn 去污染消除发丝白边() {
        // 构造半透明前景像素：50% 的黑混合 50% 的白背景 → 原图呈中灰。
        // 灰度取 205 是刻意的——它到背景色（255）的距离落在过渡带的颜色区间内
        // （默认阈值 0.12 → 下界约 30.6、上界约 70.6 色阶，205 对应距离 50），
        // 因此会被判为半透明像素，去污染修正才会真正参与运算。
        // 若取 128（距离 127）会直接被判成实心前景，测试就失去了意义。
        let mut img = RgbaImage::from_pixel(30, 30, Rgba([255, 255, 255, 255]));
        for y in 10..20 {
            for x in 14..16 {
                img.put_pixel(x, y, Rgba([205, 205, 205, 255]));
            }
        }
        let raster = RasterImage::from_image(img);

        let with = replace_background(
            &raster,
            &BackgroundOptions {
                target_color: [67, 142, 219],
                decontaminate: true,
                feather_px: 3,
                ..Default::default()
            },
        )
        .unwrap();

        let without = replace_background(
            &raster,
            &BackgroundOptions {
                target_color: [67, 142, 219],
                decontaminate: false,
                feather_px: 3,
                ..Default::default()
            },
        )
        .unwrap();

        // 统计过渡带像素的 R 通道均值：去污染后应更低（更少被背景的亮色污染）
        let rw: f32 = with
            .image
            .first()
            .pixels()
            .map(|p| p.0[0] as f32)
            .sum::<f32>()
            / (30.0 * 30.0);
        let rwo: f32 = without
            .image
            .first()
            .pixels()
            .map(|p| p.0[0] as f32)
            .sum::<f32>()
            / (30.0 * 30.0);
        assert!(
            rw <= rwo,
            "去污染后 R 通道不应高于直通合成（{rw} vs {rwo}）"
        );
    }

    #[test]
    fn 动画逐帧处理且保留延时() {
        // 两帧动画：主体在第 1、2 帧位置不同，应各自正确抠出
        let mut frames = Vec::new();
        for k in 0..2u32 {
            let mut im = RgbaImage::from_pixel(40, 40, Rgba([255, 255, 255, 255]));
            let x0 = 10 + k * 12;
            for y in 10..30 {
                for x in x0..x0 + 10 {
                    im.put_pixel(x, y, Rgba([10, 10, 10, 255]));
                }
            }
            frames.push(Frame {
                pixels: im,
                delay_ms: 120,
            });
        }
        let img = RasterImage::from_frames(40, 40, frames);
        let out = set_background_color(&img, [67, 142, 219]).unwrap();
        assert_eq!(out.image.frame_count(), 2);
        assert_eq!(out.image.frames[0].delay_ms, 120);
        // 两帧的背景都应变蓝
        assert_eq!(
            out.image.frames[1].pixels.get_pixel(1, 1).0,
            [67, 142, 219, 255]
        );
    }

    #[test]
    fn 非法参数被拒绝() {
        let img = RasterImage::from_image(white_bg_with_center(20, 20));
        let r = replace_background(
            &img,
            &BackgroundOptions {
                tolerance: 2.0,
                ..Default::default()
            },
        );
        assert!(matches!(r, Err(PicProError::InvalidArgument(_))));

        let r2 = replace_background(
            &img,
            &BackgroundOptions {
                edge_offset: 5.0,
                ..Default::default()
            },
        );
        assert!(matches!(r2, Err(PicProError::InvalidArgument(_))));
    }

    #[test]
    fn 边缘收放影响前景面积() {
        let img = RasterImage::from_image(white_bg_with_center(60, 60));
        let shrink = replace_background(
            &img,
            &BackgroundOptions {
                edge_offset: 0.5,
                ..Default::default()
            },
        )
        .unwrap();
        let grow = replace_background(
            &img,
            &BackgroundOptions {
                edge_offset: -0.5,
                ..Default::default()
            },
        )
        .unwrap();
        // 收缩前景后背景占比应更高
        assert!(
            shrink.report.background_ratio >= grow.report.background_ratio,
            "收缩前景应提高背景占比（{} vs {}）",
            shrink.report.background_ratio,
            grow.report.background_ratio
        );
    }

    /// 白底 + 中央深色方块 + 外围一圈浅灰「过渡色」。
    ///
    /// 浅灰到背景色的距离约 25 个色阶，正落在默认过渡带的上半段：
    /// 阈值低时它算前景、阈值高时被吞进背景，因此可以据此验证
    /// 「判定阈值」滑杆确实在改变像素归属。
    fn halo_ring(w: u32, h: u32) -> RgbaImage {
        let mut img = RgbaImage::from_pixel(w, h, Rgba([250, 250, 250, 255]));
        let (cx, cy) = (w as i32 / 2, h as i32 / 2);
        for y in 0..h {
            for x in 0..w {
                let d = (x as i32 - cx).abs().max((y as i32 - cy).abs());
                if d < 10 {
                    img.put_pixel(x, y, Rgba([30, 30, 30, 255]));
                } else if d < 18 {
                    img.put_pixel(x, y, Rgba([225, 225, 225, 255]));
                }
            }
        }
        img
    }

    #[test]
    fn 判定阈值越高背景占比越大() {
        let img = RasterImage::from_image(halo_ring(80, 80));
        let low = replace_background(
            &img,
            &BackgroundOptions {
                tolerance: 0.05,
                ..Default::default()
            },
        )
        .unwrap();
        let high = replace_background(
            &img,
            &BackgroundOptions {
                tolerance: 0.30,
                ..Default::default()
            },
        )
        .unwrap();
        // 阈值抬高后，浅灰过渡圈应从前景翻转为背景
        assert!(
            high.report.background_ratio > low.report.background_ratio + 0.05,
            "抬高判定阈值必须吞掉更多过渡像素（低 {} vs 高 {}）",
            low.report.background_ratio,
            high.report.background_ratio
        );
        // 中央深色主体两种阈值下都必须保留
        let px = high.image.first();
        assert!(
            px.get_pixel(40, 40).0[0] < 60,
            "主体不应被误判为背景，实际 {:?}",
            px.get_pixel(40, 40).0
        );
    }

    #[test]
    fn 边缘收放按几何像素平移边界() {
        // 80×80 白底 + 40×40 深色方块（前景占比 0.25）
        let img = RasterImage::from_image(white_bg_with_center(80, 80));
        let base = replace_background(&img, &BackgroundOptions::default()).unwrap();
        let shrink = replace_background(
            &img,
            &BackgroundOptions {
                edge_offset: 0.5,
                ..Default::default()
            },
        )
        .unwrap();
        let grow = replace_background(
            &img,
            &BackgroundOptions {
                edge_offset: -0.5,
                ..Default::default()
            },
        )
        .unwrap();

        let area = 80.0 * 80.0;
        let fg = |r: &BackgroundOutput| area * (1.0 - r.report.background_ratio);
        // 0.5 × 6px = 3px 的平移量：40×40 的方块应分别收窄/扩张为 34×34 / 46×46。
        // 断言带上容差，因为边界像素的 alpha 是渐变的，占比统计存在少量误差。
        assert!(
            (fg(&base) - 1600.0).abs() < 60.0,
            "默认参数下前景应约为 40×40=1600 像素，实际 {}",
            fg(&base)
        );
        assert!(
            (fg(&shrink) - 34.0 * 34.0).abs() < 120.0,
            "收缩 3px 后前景应约为 34×34，实际 {}",
            fg(&shrink)
        );
        assert!(
            (fg(&grow) - 46.0 * 46.0).abs() < 160.0,
            "扩张 3px 后前景应约为 46×46，实际 {}",
            fg(&grow)
        );
    }
}
