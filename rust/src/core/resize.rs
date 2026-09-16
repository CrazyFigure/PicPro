//! 缩放层：统一的高质量重采样封装。
//!
//! 使用 `fast_image_resize`（内部 SIMD 加速）而非 `image` 自带的
//! `imageops::resize`：批量处理场景下后者的速度差距明显。
//! 算法固定为 Lanczos3 —— 这是重采样质量与性能的平衡点，
//! 对证件照文字边缘、发丝这类高频细节的保持效果最好。
//!
//! 一个重要约束：**缩放带 alpha 的图必须按预乘方式处理**，
//! 否则半透明边缘会混入背景色形成灰边。`ResizeOptions` 的
//! `mul_div_alpha` 默认为 true，此处显式依赖该默认值。

use fast_image_resize::images::Image as FirImage;
use fast_image_resize::{PixelType, ResizeOptions as FirResizeOptions, Resizer};
use image::RgbaImage;

use crate::core::error::{PicProError, Result};
use crate::core::types::{Frame, RasterImage};

/// 可复用的重采样器。
///
/// `Resizer` 内部会分配工作缓冲，批量处理时应复用一个实例而不是每张图新建。
pub struct ImageResizer {
    inner: Resizer,
    options: FirResizeOptions,
}

impl Default for ImageResizer {
    fn default() -> Self {
        Self::new()
    }
}

impl ImageResizer {
    /// 创建使用 Lanczos3 的重采样器。
    pub fn new() -> Self {
        Self {
            inner: Resizer::new(),
            // 默认算法即 Lanczos3，此处显式写出以免上游改动默认值后行为漂移
            options: FirResizeOptions::new()
                .resize_alg(fast_image_resize::ResizeAlg::Convolution(
                    fast_image_resize::FilterType::Lanczos3,
                )),
        }
    }

    /// 缩放单张 RGBA 位图。
    ///
    /// 边界处理：
    /// - 目标尺寸为 0 → 报错（调用方应避免）；
    /// - 目标尺寸与源相同 → 直接克隆，跳过重采样；
    /// - 尺寸溢出 usize → 由 `fast_image_resize` 返回错误，此处转成可读信息。
    pub fn resize(&mut self, src: &RgbaImage, width: u32, height: u32) -> Result<RgbaImage> {
        if width == 0 || height == 0 {
            return Err(PicProError::InvalidArgument(format!(
                "目标尺寸非法：{width}x{height}"
            )));
        }
        if src.width() == width && src.height() == height {
            return Ok(src.clone());
        }

        let src_img = FirImage::from_vec_u8(
            src.width(),
            src.height(),
            src.as_raw().clone(),
            PixelType::U8x4,
        )
        .map_err(|e| PicProError::Encode(format!("构造缩放源缓冲失败：{e}")))?;

        let mut dst_img = FirImage::new(width, height, PixelType::U8x4);
        self.inner
            .resize(&src_img, &mut dst_img, &self.options)
            .map_err(|e| PicProError::Encode(format!("缩放失败：{e}")))?;

        // into_vec 的长度已由构造时按像素类型确定，此处可安全接管
        RgbaImage::from_raw(width, height, dst_img.into_vec())
            .ok_or_else(|| PicProError::Encode("缩放结果缓冲尺寸不匹配".into()))
    }

    /// 缩放整张图（含全部动画帧）。
    ///
    /// 动画各帧尺寸必须保持一致，否则编码器会拒绝写出。
    pub fn resize_image(&mut self, img: &RasterImage, width: u32, height: u32) -> Result<RasterImage> {
        let mut frames = Vec::with_capacity(img.frames.len());
        for f in &img.frames {
            frames.push(Frame {
                pixels: self.resize(&f.pixels, width, height)?,
                // 帧延时必须原样保留，否则动画节奏会变
                delay_ms: f.delay_ms,
            });
        }
        Ok(RasterImage::from_frames(width, height, frames))
    }

    /// 按比例等比缩放。
    ///
    /// 比例非法（<=0 或非有限值）时报错，避免产生 0 尺寸图。
    pub fn scale(&mut self, img: &RasterImage, factor: f32) -> Result<RasterImage> {
        if !factor.is_finite() || factor <= 0.0 {
            return Err(PicProError::InvalidArgument(format!(
                "缩放比例非法：{factor}"
            )));
        }
        let w = ((img.width as f32 * factor).round() as u32).max(1);
        let h = ((img.height as f32 * factor).round() as u32).max(1);
        self.resize_image(img, w, h)
    }

    /// 等比缩放到不超过指定边框内，返回实际尺寸。
    ///
    /// 用于「限制长边」「限制最大宽高」这类场景。
    /// `allow_upscale` 为 false 时，原图已小于边框则原样返回（不放大）。
    pub fn fit_within(
        &mut self,
        img: &RasterImage,
        max_width: u32,
        max_height: u32,
        allow_upscale: bool,
    ) -> Result<RasterImage> {
        if max_width == 0 || max_height == 0 {
            return Err(PicProError::InvalidArgument(format!(
                "边框尺寸非法：{max_width}x{max_height}"
            )));
        }
        // 取两个方向缩放比中的较小值，保证长边落入边框
        let ratio_w = max_width as f32 / img.width as f32;
        let ratio_h = max_height as f32 / img.height as f32;
        let ratio = ratio_w.min(ratio_h);
        if ratio >= 1.0 && !allow_upscale {
            return Ok(img.clone());
        }
        let w = ((img.width as f32 * ratio).round() as u32).max(1);
        let h = ((img.height as f32 * ratio).round() as u32).max(1);
        self.resize_image(img, w, h)
    }

    /// 把长边限制到 `max_long_side`（不放大）。
    pub fn fit_long_side(&mut self, img: &RasterImage, max_long_side: u32) -> Result<RasterImage> {
        let long = img.width.max(img.height);
        if long <= max_long_side {
            return Ok(img.clone());
        }
        let factor = max_long_side as f32 / long as f32;
        self.scale(img, factor)
    }
}

/// 便捷函数：一次性缩放（内部新建重采样器）。批量场景请改用 [`ImageResizer`]。
pub fn resize_rgba(src: &RgbaImage, width: u32, height: u32) -> Result<RgbaImage> {
    ImageResizer::new().resize(src, width, height)
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::Rgba;

    #[test]
    fn 等比缩放保持宽高比() {
        let img = RasterImage::from_image(RgbaImage::from_pixel(400, 200, Rgba([10, 20, 30, 255])));
        let mut r = ImageResizer::new();
        let out = r.fit_long_side(&img, 100).unwrap();
        // 长边 400 -> 100，短边应等比降到 50
        assert_eq!((out.width, out.height), (100, 50));
    }

    #[test]
    fn fit_within不放大() {
        let img = RasterImage::from_image(RgbaImage::from_pixel(50, 50, Rgba([1, 2, 3, 255])));
        let mut r = ImageResizer::new();
        let out = r.fit_within(&img, 1000, 1000, false).unwrap();
        assert_eq!((out.width, out.height), (50, 50), "不应放大");
    }

    #[test]
    fn fit_within允许放大时按比例放大() {
        let img = RasterImage::from_image(RgbaImage::from_pixel(50, 25, Rgba([1, 2, 3, 255])));
        let mut r = ImageResizer::new();
        let out = r.fit_within(&img, 200, 200, true).unwrap();
        // 50x25 放入 200x200 的框：受宽度限制，放大 4 倍得到 200x100，
        // 高度虽有余量也不应拉伸（fit_within 保持宽高比）
        assert_eq!((out.width, out.height), (200, 100));
    }

    #[test]
    fn 尺寸相同直接返回且内容一致() {
        let src = RgbaImage::from_pixel(8, 8, Rgba([9, 8, 7, 255]));
        let out = resize_rgba(&src, 8, 8).unwrap();
        assert_eq!(out.get_pixel(0, 0).0, [9, 8, 7, 255]);
    }

    #[test]
    fn 非法尺寸与非法比例均报错() {
        let img = RasterImage::from_image(RgbaImage::from_pixel(10, 10, Rgba([0, 0, 0, 255])));
        let mut r = ImageResizer::new();
        assert!(matches!(
            r.resize_image(&img, 0, 10),
            Err(PicProError::InvalidArgument(_))
        ));
        assert!(matches!(
            r.scale(&img, 0.0),
            Err(PicProError::InvalidArgument(_))
        ));
        assert!(matches!(
            r.scale(&img, f32::NAN),
            Err(PicProError::InvalidArgument(_))
        ));
    }

    #[test]
    fn 缩放松弛图时保留全部帧与延时() {
        let mut frames = Vec::new();
        for i in 0..3u8 {
            frames.push(crate::core::types::Frame {
                pixels: RgbaImage::from_pixel(20, 20, Rgba([i * 50, 0, 0, 255])),
                delay_ms: 80 + i as u32,
            });
        }
        let img = RasterImage::from_frames(20, 20, frames);
        let mut r = ImageResizer::new();
        let out = r.resize_image(&img, 10, 10).unwrap();
        assert_eq!(out.frame_count(), 3);
        assert_eq!(out.frames[0].delay_ms, 80);
        assert_eq!(out.frames[2].delay_ms, 82);
        // 每帧尺寸都应同步缩到目标尺寸
        assert_eq!(out.frames[1].pixels.width(), 10);
    }

    #[test]
    fn 纯色区域缩放后仍为原色() {
        // 纯色图做下采样不应引入色偏，可用于发现预乘/通道错位等错误
        let src = RgbaImage::from_pixel(100, 100, Rgba([200, 100, 50, 255]));
        let out = resize_rgba(&src, 37, 41).unwrap();
        let px = out.get_pixel(18, 20).0;
        assert!(
            (px[0] as i32 - 200).abs() <= 2
                && (px[1] as i32 - 100).abs() <= 2
                && (px[2] as i32 - 50).abs() <= 2,
            "纯色缩放后应保持原色，实际 {px:?}"
        );
    }
}
