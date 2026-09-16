//! 裁剪：按证件照规格把原图裁到指定比例与像素。
//!
//! 裁剪框用**归一化坐标**（0~1，相对原图）表达，好处是：
//! - 界面上的拖动结果可直接喂给内核，不必关心原图像素尺寸；
//! - 同一组坐标可用在预览缩略图与全分辨率处理两条路径上，结果一致。
//!
//! 证件照的构图要求（人脸水平居中、眼睛位于画面上方 30%~50%、
//! 头肩占比约 2/3）由界面辅助线引导，内核负责保证像素精确。

use image::RgbaImage;

use crate::core::error::{PicProError, Result};
use crate::core::resize::ImageResizer;
use crate::core::types::{Frame, RasterImage};

/// 归一化裁剪框（相对源图的比例，取值 0~1）。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CropRect {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

impl CropRect {
    /// 新建裁剪框（不做校验，校验在 [`crop`] 里统一做）。
    pub fn new(x: f32, y: f32, width: f32, height: f32) -> Self {
        Self {
            x,
            y,
            width,
            height,
        }
    }

    /// 全图（不裁剪）。
    pub fn full() -> Self {
        Self::new(0.0, 0.0, 1.0, 1.0)
    }

    /// 裁剪框对应的**实际像素**宽高比。
    ///
    /// 注意：不能直接用 `width / height` 判断比例——归一化矩形的宽高比
    /// 与像素宽高比只在正方形原图上才相等（例如在 1000×500 的图上，
    /// 归一化 0.375×1.0 的框实际是 375×500 像素，比例为 0.75 而非 0.375）。
    /// 校验构图比例必须走本方法。
    pub fn pixel_aspect(&self, img_w: u32, img_h: u32) -> f32 {
        let ph = self.height * img_h as f32;
        if ph <= 0.0 {
            0.0
        } else {
            (self.width * img_w as f32) / ph
        }
    }

    /// 把裁剪框收敛到合法范围：宽高限定在 (0,1]，位置保证不越界。
    ///
    /// 浮点误差与界面拖动都可能产生越界值，统一在此处夹紧，
    /// 避免后续取像素时出现越界 panic。
    pub fn clamp_to_bounds(&self) -> Self {
        // 先保证宽高为有效正数
        let w = self.width.clamp(1e-4, 1.0);
        let h = self.height.clamp(1e-4, 1.0);
        // 再让左上角落在 [0, 1-w] 内，确保右下角不超出
        let x = self.x.clamp(0.0, 1.0 - w);
        let y = self.y.clamp(0.0, 1.0 - h);
        Self::new(x, y, w, h)
    }
}

/// 把归一化矩形换算成像素矩形 `(left, top, width, height)`。
///
/// 边界处理：四舍五入后宽高至少为 1 像素，并夹紧到图像范围内，
/// 保证返回值一定能用于取图。
pub fn to_pixel_rect(rect: &CropRect, img_w: u32, img_h: u32) -> (u32, u32, u32, u32) {
    let r = rect.clamp_to_bounds();
    let left = (r.x * img_w as f32).floor().max(0.0) as u32;
    let top = (r.y * img_h as f32).floor().max(0.0) as u32;
    let mut w = (r.width * img_w as f32).round().max(1.0) as u32;
    let mut h = (r.height * img_h as f32).round().max(1.0) as u32;
    // 夹紧到图像边界内，防止超出后取图失败
    w = w.min(img_w.saturating_sub(left).max(1));
    h = h.min(img_h.saturating_sub(top).max(1));
    // 若夹紧后右下角仍越界（极端取整情况），回退到剩余可用区域
    let left = left.min(img_w.saturating_sub(1));
    let top = top.min(img_h.saturating_sub(1));
    (left, top, w, h)
}

/// 按归一化矩形裁剪（含全部动画帧）。
///
/// 若裁剪框已覆盖全图，直接返回副本，避免无谓的像素拷贝。
pub fn crop(img: &RasterImage, rect: &CropRect) -> Result<RasterImage> {
    let r = rect.clamp_to_bounds();
    if (r.x).abs() < 1e-6
        && (r.y).abs() < 1e-6
        && (r.width - 1.0).abs() < 1e-6
        && (r.height - 1.0).abs() < 1e-6
    {
        return Ok(img.clone());
    }

    let (left, top, w, h) = to_pixel_rect(&r, img.width, img.height);
    if w == 0 || h == 0 {
        return Err(PicProError::InvalidArgument("裁剪区域为空".into()));
    }

    let mut frames = Vec::with_capacity(img.frames.len());
    for f in &img.frames {
        frames.push(Frame {
            pixels: crop_rgba(&f.pixels, left, top, w, h),
            // 帧延时必须保留
            delay_ms: f.delay_ms,
        });
    }
    Ok(RasterImage::from_frames(w, h, frames))
}

/// 从 RGBA 位图取子矩形。
///
/// 直接按行拷贝而非走 `GenericImageView::view`，避免某些实现下的边界检查开销。
fn crop_rgba(src: &RgbaImage, left: u32, top: u32, w: u32, h: u32) -> RgbaImage {
    let mut out = RgbaImage::new(w, h);
    let src_stride = src.width() as usize * 4;
    let raw = src.as_raw();
    let out_stride = w as usize * 4;
    for row in 0..h as usize {
        let src_start = (top as usize + row) * src_stride + left as usize * 4;
        let dst_start = row * out_stride;
        // 取目标缓冲区对应行的切片后整体拷贝，避免逐像素写入的边界检查开销
        let dst = &mut out.as_mut()[dst_start..dst_start + out_stride];
        dst.copy_from_slice(&raw[src_start..src_start + out_stride]);
    }
    out
}

/// 裁剪后缩放到精确像素。
///
/// 这是证件照处理的标准路径：规格要求同时约束「宽高比」与「精确像素」，
/// 而裁剪框的比例未必与目标完全一致（用户拖动会有微小偏差），
/// 因此裁剪之后必须再缩放到目标像素，保证输出严格合规。
pub fn crop_to_exact_size(
    img: &RasterImage,
    rect: &CropRect,
    out_width: u32,
    out_height: u32,
) -> Result<RasterImage> {
    if out_width == 0 || out_height == 0 {
        return Err(PicProError::InvalidArgument(format!(
            "目标尺寸非法：{out_width}x{out_height}"
        )));
    }
    let cropped = crop(img, rect)?;
    // 已恰好是目标尺寸则跳过重采样，避免二次插值损失
    if cropped.width == out_width && cropped.height == out_height {
        return Ok(cropped);
    }
    ImageResizer::new().resize_image(&cropped, out_width, out_height)
}

/// 按目标宽高比居中裁剪（水平居中，纵向按 `vertical_anchor` 定位）。
///
/// `vertical_anchor` 表示裁剪框顶端相对原图高度的位置：
/// - 0.0 = 贴顶（适合头像偏上的证件照，默认值 0.06 给头顶留少量余量）
/// - 0.5 = 纵向居中
///
/// 这是「用户未手动调整裁剪框」时的默认构图：人像照的头部通常在画面上部，
/// 直接居中裁剪容易把头顶切掉。
pub fn centered_aspect_crop(
    img: &RasterImage,
    aspect_width: f32,
    aspect_height: f32,
    vertical_anchor: f32,
) -> Result<RasterImage> {
    if aspect_width <= 0.0 || aspect_height <= 0.0 {
        return Err(PicProError::InvalidArgument(format!(
            "目标宽高比非法：{aspect_width}:{aspect_height}"
        )));
    }
    let rect = suggest_crop_rect(img, aspect_width, aspect_height, vertical_anchor);
    crop(img, &rect)
}

/// 计算建议裁剪框：在保持目标宽高比的前提下取最大可用区域。
///
/// 返回归一化坐标，可直接交给界面作为初始裁剪框，也能直接用于 [`crop`]。
pub fn suggest_crop_rect(
    img: &RasterImage,
    aspect_width: f32,
    aspect_height: f32,
    vertical_anchor: f32,
) -> CropRect {
    let target_aspect = aspect_width / aspect_height;
    let img_aspect = img.width as f32 / img.height as f32;

    // 以「宽度受限」还是「高度受限」决定裁剪框大小
    let (w, h) = if img_aspect > target_aspect {
        // 原图更宽：高度占满，宽度按比例收窄
        (target_aspect / img_aspect, 1.0)
    } else {
        // 原图更高：宽度占满，高度按比例收窄
        (1.0, img_aspect / target_aspect)
    };

    // 水平居中
    let x = (1.0 - w) / 2.0;
    // 纵向按锚点定位，并夹紧到不越界
    let y = vertical_anchor.clamp(0.0, 1.0 - h);
    CropRect::new(x, y, w, h).clamp_to_bounds()
}

/// 计算让裁剪框满足指定宽高比、且包含给定人脸的矩形。
///
/// 用于「检测到人脸后自动构图」：保证人脸中心位于画面中部，
/// 并按证件照惯例让眼睛大致落在画面上方 40% 处。
///
/// `face` 为人脸框的归一化坐标。无法满足时退化为 [`suggest_crop_rect`]。
pub fn crop_rect_around_face(
    img: &RasterImage,
    aspect_width: f32,
    aspect_height: f32,
    face: &CropRect,
) -> CropRect {
    let base = suggest_crop_rect(img, aspect_width, aspect_height, 0.0);
    // 人脸中心：水平居中，纵向按「人脸中心落在裁剪框 40% 高度处」对齐
    let face_cx = face.x + face.width / 2.0;
    let face_cy = face.y + face.height / 2.0;

    // 期望：人脸中心位于裁剪框高度的 40% 位置
    let eye_line_ratio = 0.40;
    let y = face_cy - base.height * eye_line_ratio;
    let x = face_cx - base.width / 2.0;

    CropRect::new(x, y, base.width, base.height).clamp_to_bounds()
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::Rgba;

    fn checker(w: u32, h: u32) -> RasterImage {
        let mut px = RgbaImage::new(w, h);
        for y in 0..h {
            for x in 0..w {
                // 用坐标编码颜色，便于验证裁剪位置是否正确
                px.put_pixel(x, y, Rgba([x as u8, y as u8, 0, 255]));
            }
        }
        RasterImage::from_image(px)
    }

    #[test]
    fn 裁剪取到正确区域() {
        let img = checker(100, 100);
        // 从 (20,30) 开始取 40x50
        let out = crop(&img, &CropRect::new(0.2, 0.3, 0.4, 0.5)).unwrap();
        assert_eq!((out.width, out.height), (40, 50));
        // 左上角像素应来自原图 (20,30)
        assert_eq!(out.first().get_pixel(0, 0).0, [20, 30, 0, 255]);
    }

    #[test]
    fn 全图裁剪直接返回且内容一致() {
        let img = checker(30, 20);
        let out = crop(&img, &CropRect::full()).unwrap();
        assert_eq!((out.width, out.height), (30, 20));
    }

    #[test]
    fn 越界裁剪框被夹紧而不panic() {
        let img = checker(50, 50);
        // x/y 为负、宽高超过 1，应被夹紧到合法范围
        let out = crop(&img, &CropRect::new(-0.5, -0.5, 2.0, 2.0)).unwrap();
        assert_eq!((out.width, out.height), (50, 50));
    }

    #[test]
    fn 裁剪后缩放到精确像素() {
        let img = checker(600, 800);
        // 目标 295x413（标准一寸），验证裁剪+缩放后严格等于目标像素
        let out = crop_to_exact_size(&img, &CropRect::full(), 295, 413).unwrap();
        assert_eq!((out.width, out.height), (295, 413));
    }

    #[test]
    fn 建议裁剪框保持目标宽高比且不越界() {
        let img = checker(1000, 500); // 宽图
        let r = suggest_crop_rect(&img, 3.0, 4.0, 0.06);
        // 必须按像素宽高比校验：归一化矩形的宽高比在此图上会失真
        assert!(
            (r.pixel_aspect(1000, 500) - 0.75).abs() < 0.01,
            "实际像素宽高比应为 3:4，得到 {}",
            r.pixel_aspect(1000, 500)
        );
        assert!(r.x >= 0.0 && r.y >= 0.0);
        assert!(r.x + r.width <= 1.0001 && r.y + r.height <= 1.0001);
    }

    #[test]
    fn 竖向图片的建议裁剪框宽度占满() {
        let img = checker(400, 1000); // 高图，目标 3:4 比原图更宽
        let r = suggest_crop_rect(&img, 3.0, 4.0, 0.0);
        // 高图裁 3:4 时宽度受限，应占满宽度
        assert!((r.width - 1.0).abs() < 1e-6, "宽度应占满，实际 {}", r.width);
        assert!(r.height < 1.0);
    }

    #[test]
    fn 人脸构图让人脸中心落在上半部() {
        // 必须用「比目标 3:4 更瘦长」的原图（600x1000=0.6），
        // 此时裁剪框高度小于画布，纵向才有调整余量；
        // 若原图宽高比恰为 3:4，裁剪框铺满全图，纵向上无自由度。
        let img = checker(600, 1000);
        // 人脸中心 (0.5, 0.45)
        let face = CropRect::new(0.4, 0.35, 0.2, 0.2);
        let r = crop_rect_around_face(&img, 3.0, 4.0, &face);

        let face_cy = face.y + face.height / 2.0;
        let relative = (face_cy - r.y) / r.height;
        assert!(
            (relative - 0.40).abs() < 0.02,
            "人脸中心相对位置应约 0.40，实际 {relative}"
        );
        // 水平应居中
        let face_cx = face.x + face.width / 2.0;
        let rel_x = (face_cx - r.x) / r.width;
        assert!((rel_x - 0.5).abs() < 0.02, "人脸应水平居中，实际 {rel_x}");
        // 构图结果仍须满足目标比例且不越界
        assert!((r.pixel_aspect(600, 1000) - 0.75).abs() < 0.01);
        assert!(r.y >= 0.0 && r.y + r.height <= 1.0001);
    }

    #[test]
    fn 人脸过于靠顶时夹紧而不越界() {
        // 边界情况：人脸靠顶，理想裁剪框会落在画布外，
        // 此时必须夹紧到 0，而不是返回负坐标
        let img = checker(600, 1000);
        let face = CropRect::new(0.4, 0.02, 0.2, 0.2); // 中心约 0.12
        let r = crop_rect_around_face(&img, 3.0, 4.0, &face);
        assert!(r.y >= 0.0, "裁剪框不得越过上边界，实际 y={}", r.y);
        assert!(r.y + r.height <= 1.0001);
    }

    #[test]
    fn 动画图裁剪保留帧数与延时() {
        let mut frames = Vec::new();
        for i in 0..3u8 {
            frames.push(Frame {
                pixels: RgbaImage::from_pixel(20, 20, Rgba([i * 10, 5, 5, 255])),
                delay_ms: 60,
            });
        }
        let img = RasterImage::from_frames(20, 20, frames);
        let out = crop(&img, &CropRect::new(0.0, 0.0, 0.5, 0.5)).unwrap();
        assert_eq!(out.frame_count(), 3);
        assert_eq!(out.frames[0].delay_ms, 60);
        assert_eq!((out.width, out.height), (10, 10));
    }

    #[test]
    fn 零尺寸目标被拒绝() {
        let img = checker(10, 10);
        let r = crop_to_exact_size(&img, &CropRect::full(), 0, 100);
        assert!(matches!(r, Err(PicProError::InvalidArgument(_))));
    }
}
