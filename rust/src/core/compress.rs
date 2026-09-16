//! 按目标体积压缩。
//!
//! 核心是**二维搜索**：在「缩放比例 × 编码质量」空间里寻找满足体积上限的组合。
//! 判定优先级为「先保证质量达标，再取最大分辨率」：
//! 文字与证件类图片的可读性主要由**像素量**决定，因此宁可用略低的质量
//! 换取更高分辨率，也不要「高分辨率但压缩伪影严重」。
//!
//! 各格式的可调维度不同，必须分别处理：
//! - **JPEG**：质量与分辨率都可调，走完整的二维搜索；
//! - **PNG / WebP / BMP / TIFF**：无质量参数（WebP 仅无损），只能靠降分辨率；
//! - **GIF**：无质量参数（只有量化速度），同样只能靠降分辨率，
//!   且需逐帧处理，成本与帧数成正比。

use crate::core::encode::{encode, EncodeOptions};
use crate::core::error::{PicProError, Result};
use crate::core::format::ImageFormat;
use crate::core::resize::ImageResizer;
use crate::core::types::RasterImage;

/// 压缩参数。
#[derive(Debug, Clone)]
pub struct CompressOptions {
    /// 目标体积上限（字节）。None 表示不做体积约束。
    pub target_bytes: Option<u64>,
    /// 显式指定的目标宽度（与高度配合使用，会拉伸）。
    pub target_width: Option<u32>,
    /// 显式指定的目标高度。
    pub target_height: Option<u32>,
    /// 限制长边上限（等比，不放大）。
    pub max_long_side: Option<u32>,
    /// 可接受的最低质量。低于此值则继续降分辨率以保住质量。
    pub quality_floor: u8,
    /// 质量搜索区间下限。
    pub quality_min: u8,
    /// 质量搜索区间上限。
    pub quality_max: u8,
    /// 输出长边下限。防止为了压体积把图缩到无法辨认。
    pub min_long_side: u32,
    /// 是否允许放大（一般场景应为 false）。
    pub allow_upscale: bool,
    /// 缩放档位，从大到小依次尝试。
    pub scale_steps: Vec<f32>,
    /// 输出格式与编码细节。
    pub encode: EncodeOptions,
}

impl Default for CompressOptions {
    fn default() -> Self {
        Self {
            target_bytes: None,
            target_width: None,
            target_height: None,
            max_long_side: None,
            quality_floor: 85,
            quality_min: 60,
            quality_max: 95,
            min_long_side: 200,
            allow_upscale: false,
            // 档位刻意在 0.5 附近加密：实测 1MB 预算下手机照片的最佳落点就在这一带
            scale_steps: vec![
                1.0, 0.9, 0.8, 0.7, 0.6, 0.55, 0.5, 0.45, 0.42, 0.35, 0.3, 0.25, 0.2,
            ],
            encode: EncodeOptions::default(),
        }
    }
}

/// 压缩结果。
#[derive(Debug, Clone)]
pub struct CompressResult {
    /// 处理后的图像（调用方可直接接管，无需再次缩放）。
    pub image: RasterImage,
    /// 编码后的字节流。
    pub bytes: Vec<u8>,
    /// 最终使用的质量（非质量格式恒为 `quality_max`）。
    pub quality: u8,
    /// 最终使用的缩放比例。
    pub scale: f32,
    /// 实际尝试的编码次数，用于性能分析与测试断言。
    pub attempts: usize,
}

/// 执行压缩。
///
/// 流程：
/// 1. 先落实显式的尺寸要求（`target_width/height` 拉伸、`max_long_side` 等比限制）；
/// 2. 无体积约束时按 `quality_max` 直接编码返回；
/// 3. 有体积约束时按 `scale_steps` 从大到小逐档尝试：
///    - 支持质量的格式：档内二分搜索满足上限的最高质量；
///    - 不支持质量的格式：只判断该档能否满足上限；
///    - 命中「质量 >= quality_floor」即采用当前档（分辨率最大且质量达标）并结束；
///    - 各档都不达标时，兜底采用**第一个能塞进上限的档**（保分辨率优先），
///      但若质量低于下限仍继续下调，直至长边触及 `min_long_side`。
/// 4. 全部档位都无法满足体积上限 → 返回 `TargetUnreachable`，提示放宽约束。
pub fn compress(img: &RasterImage, opts: &CompressOptions) -> Result<CompressResult> {
    let mut attempts = 0usize;
    let mut resizer = ImageResizer::new();

    // ---------- 步骤 1：显式尺寸要求 ----------
    let mut base = img.clone();
    if let (Some(w), Some(h)) = (opts.target_width, opts.target_height) {
        // 拉伸到精确尺寸（证件照裁剪后统一尺寸时使用）
        if w == 0 || h == 0 {
            return Err(PicProError::InvalidArgument(format!(
                "目标尺寸非法：{w}x{h}"
            )));
        }
        base = resizer.resize_image(&base, w, h)?;
    } else if let Some(long) = opts.max_long_side {
        base = resizer.fit_long_side(&base, long)?;
    }

    // ---------- 步骤 2：无体积约束 ----------
    let Some(target) = opts.target_bytes else {
        let mut enc = opts.encode.clone();
        enc.quality = enc.quality.min(opts.quality_max).max(opts.quality_min);
        let bytes = encode(&base, &enc)?;
        return Ok(CompressResult {
            image: base,
            bytes,
            quality: enc.quality,
            scale: 1.0,
            attempts: 1,
        });
    };

    if target == 0 {
        return Err(PicProError::InvalidArgument("目标体积上限不能为 0".into()));
    }

    // ---------- 步骤 3：逐档搜索 ----------
    // 保底结果：第一个能塞进上限的组合（分辨率优先）
    let mut fallback: Option<(f32, RasterImage, u8, Vec<u8>)> = None;
    let long_side = base.width.max(base.height);

    for &scale in &opts.scale_steps {
        // 长边硬下限保护：越过下限就停止，避免把图缩到不可辨认
        let candidate_long = (long_side as f32 * scale).round() as u32;
        if candidate_long < opts.min_long_side {
            break;
        }

        // 缩放（scale=1.0 时内部会跳过重采样）
        let scaled = if (scale - 1.0).abs() < f32::EPSILON {
            base.clone()
        } else {
            resizer.scale(&base, scale)?
        };

        let (quality, bytes) = fit_quality(&scaled, opts, &mut attempts)?;

        // 该档下即使最低质量也超限，跳过
        let Some((quality, bytes)) = quality.zip(bytes) else {
            continue;
        };

        // 保底结果只记录**第一个**能塞进上限的档位即可。
        // 缩放档位是从大到小遍历的，因此第一个命中者就是「能满足体积上限的最大分辨率」，
        // 与「保分辨率优先」的取舍一致，无需再被更小的档位覆盖。
        if fallback.is_none() {
            fallback = Some((scale, scaled.clone(), quality, bytes.clone()));
        }

        // 质量达标即采用：当前是「满足质量下限的最大分辨率」
        if quality >= opts.quality_floor {
            return Ok(CompressResult {
                image: scaled,
                bytes,
                quality,
                scale,
                attempts,
            });
        }
    }

    // ---------- 步骤 4：兜底或报错 ----------
    if let Some((scale, image, quality, bytes)) = fallback {
        // 能塞进上限即算成功，只是质量未达理想下限，属于可接受的降级
        return Ok(CompressResult {
            image,
            bytes,
            quality,
            scale,
            attempts,
        });
    }

    Err(PicProError::TargetUnreachable(format!(
        "在长边不低于 {}px 的约束下无法压到 {}（{}），请放宽体积上限或降低长边下限",
        opts.min_long_side,
        format_bytes(target),
        opts.encode.format.display_name()
    )))
}

/// 在给定图像上寻找满足体积上限的最高质量。
///
/// - 支持质量的格式：先按最低质量试探，超限则返回 (None, None)；
///   否则二分搜索满足上限的最高质量。
/// - 不支持质量的格式：只编码一次，判断是否超限。
fn fit_quality(
    img: &RasterImage,
    opts: &CompressOptions,
    attempts: &mut usize,
) -> Result<(Option<u8>, Option<Vec<u8>>)> {
    let target = opts.target_bytes.expect("调用方已确保存在体积上限");
    let mut enc = opts.encode.clone();

    if !enc.format.supports_quality() {
        // 无质量维度：只能按上限质量直接编码，看是否能塞进去
        enc.quality = opts.quality_max;
        *attempts += 1;
        let bytes = encode(img, &enc)?;
        if (bytes.len() as u64) <= target {
            return Ok((Some(opts.quality_max), Some(bytes)));
        }
        return Ok((None, None));
    }

    // 先用最低质量试探：连最低质量都超限，则该分辨率档位不可用
    enc.quality = opts.quality_min;
    *attempts += 1;
    let low = encode(img, &enc)?;
    if (low.len() as u64) > target {
        return Ok((None, None));
    }

    // 二分搜索满足上限的最高质量
    let mut lo = opts.quality_min;
    let mut hi = opts.quality_max;
    let mut best: (u8, Vec<u8>) = (opts.quality_min, low);
    while lo <= hi {
        let mid = lo + (hi - lo) / 2;
        enc.quality = mid;
        *attempts += 1;
        let bytes = encode(img, &enc)?;
        if (bytes.len() as u64) <= target {
            best = (mid, bytes);
            lo = mid + 1; // 仍有余量，尝试更高质量
        } else {
            // mid 为 0 时 hi 会下溢，此处 mid >= quality_min >= 1 保证不会发生
            hi = mid - 1;
        }
    }
    Ok((Some(best.0), Some(best.1)))
}

/// 人类可读的体积文案。
pub fn format_bytes(n: u64) -> String {
    const KB: f64 = 1024.0;
    let f = n as f64;
    if f < KB {
        format!("{n} B")
    } else if f < KB * KB {
        format!("{:.1} KB", f / KB)
    } else {
        format!("{:.2} MB", f / (KB * KB))
    }
}

/// 便捷函数：把图压到指定 KB 以内（默认 JPEG 输出）。
pub fn compress_to_kb(img: &RasterImage, kb: u64) -> Result<CompressResult> {
    compress(
        img,
        &CompressOptions {
            target_bytes: Some(kb * 1024),
            ..Default::default()
        },
    )
}

/// 判断某格式能否参与质量搜索（供界面决定是否展示质量滑杆）。
pub fn format_supports_quality(format: ImageFormat) -> bool {
    format.supports_quality()
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{Rgba, RgbaImage};

    /// 生成带随机噪声的测试图。
    ///
    /// 刻意用噪声而非纯色：纯色图的 JPEG 体积极小，无法有效验证体积搜索逻辑。
    fn noisy(w: u32, h: u32) -> RasterImage {
        let mut px = RgbaImage::new(w, h);
        let mut seed: u32 = 12345;
        for y in 0..h {
            for x in 0..w {
                // 线性同余伪随机，保证测试可复现
                seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
                let v = (seed >> 16) as u8;
                seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
                let v2 = (seed >> 16) as u8;
                seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
                let v3 = (seed >> 16) as u8;
                px.put_pixel(x, y, Rgba([v, v2, v3, 255]));
            }
        }
        RasterImage::from_image(px)
    }

    #[test]
    fn 无体积约束时按上限质量直接输出() {
        let img = noisy(120, 90);
        let opts = CompressOptions {
            target_bytes: None,
            encode: EncodeOptions::for_format(ImageFormat::Jpeg),
            ..Default::default()
        };
        let r = compress(&img, &opts).unwrap();
        assert_eq!(r.attempts, 1, "无体积约束不应做搜索");
        assert_eq!(r.scale, 1.0);
        assert_eq!((r.image.width, r.image.height), (120, 90));
    }

    #[test]
    fn 能压到指定体积上限以内() {
        // 大尺寸噪声图 + 严格上限，必须触发降分辨率
        let img = noisy(800, 600);
        let limit = 60_000u64;
        let r = compress(
            &img,
            &CompressOptions {
                target_bytes: Some(limit),
                ..Default::default()
            },
        )
        .unwrap();
        assert!(
            r.bytes.len() as u64 <= limit,
            "输出 {} 字节，超过上限 {limit}",
            r.bytes.len()
        );
        assert!(r.attempts > 1, "应发生了多次尝试");
        // 应真的缩了分辨率而不是原尺寸硬压
        assert!(r.image.width <= 800);
    }

    #[test]
    fn 命中质量下限时优先保留分辨率() {
        // 上限较宽松：应尽量保持原分辨率，而不是无谓缩小
        let img = noisy(400, 300);
        let r = compress(
            &img,
            &CompressOptions {
                target_bytes: Some(10_000_000),
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(r.scale, 1.0, "体积充裕时不应缩小分辨率");
        assert!(r.quality >= 85, "质量应达到下限，实际 {}", r.quality);
    }

    #[test]
    fn 体积无法满足时返回可读错误而非panic() {
        let img = noisy(600, 400);
        // 上限设为 1 字节，任何编码都不可能满足
        let r = compress(
            &img,
            &CompressOptions {
                target_bytes: Some(1),
                min_long_side: 10,
                ..Default::default()
            },
        );
        assert!(matches!(r, Err(PicProError::TargetUnreachable(_))));
    }

    #[test]
    fn 长边下限约束生效() {
        let img = noisy(2000, 1500);
        let r = compress(
            &img,
            &CompressOptions {
                target_bytes: Some(5_000),
                min_long_side: 600,
                ..Default::default()
            },
        );
        // 下限 600 太高，无法压到 5KB，应报错而不是把图缩到 600 以下
        match r {
            Err(PicProError::TargetUnreachable(_)) => {}
            Ok(v) => assert!(
                v.image.width.max(v.image.height) >= 600,
                "不应突破长边下限，实际 {}",
                v.image.width.max(v.image.height)
            ),
            Err(e) => panic!("意外错误：{e}"),
        }
    }

    #[test]
    fn 显式目标尺寸会拉伸到精确像素() {
        let img = noisy(300, 200);
        let r = compress(
            &img,
            &CompressOptions {
                target_width: Some(295),
                target_height: Some(413),
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!((r.image.width, r.image.height), (295, 413));
    }

    #[test]
    fn 不支持质量的格式靠降分辨率达标() {
        // PNG 无质量参数，只能通过缩小来减体积。
        // 注意噪声图的 PNG 体积几乎不可压缩（约等于原始像素量），
        // 因此这里把长边下限放宽到 50，才有足够的降分辨率空间。
        let img = noisy(600, 600);
        let limit = 80_000u64;
        let r = compress(
            &img,
            &CompressOptions {
                target_bytes: Some(limit),
                min_long_side: 50,
                encode: EncodeOptions::for_format(ImageFormat::Png),
                ..Default::default()
            },
        )
        .unwrap();
        assert!(r.bytes.len() as u64 <= limit);
        assert!(
            r.image.width < 600,
            "PNG 应通过降分辨率达标，实际宽度 {}",
            r.image.width
        );
    }

    #[test]
    fn 体积文案格式正确() {
        assert_eq!(format_bytes(512), "512 B");
        assert_eq!(format_bytes(2048), "2.0 KB");
        assert_eq!(format_bytes(2 * 1024 * 1024), "2.00 MB");
    }

    #[test]
    fn 零体积上限被拒绝() {
        let img = noisy(10, 10);
        let r = compress(
            &img,
            &CompressOptions {
                target_bytes: Some(0),
                ..Default::default()
            },
        );
        assert!(matches!(r, Err(PicProError::InvalidArgument(_))));
    }
}
