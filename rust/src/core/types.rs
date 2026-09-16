//! 内核统一的内存图像表示。
//!
//! 所有解码结果统一为 **RGBA8 多帧**结构：
//! - 统一 RGBA 是为了让换背景、羽化、合成等操作只处理一种像素布局；
//! - 多帧是为了保留 GIF/WebP 动画；
//! - 静态图就是「只有一帧」的多帧图，不额外分类型，避免上下两条代码路径。

use image::{Rgba, RgbaImage};

/// 单帧位图。
#[derive(Debug, Clone)]
pub struct Frame {
    /// RGBA8 像素缓冲，尺寸与所属 `RasterImage` 一致
    pub pixels: RgbaImage,
    /// 该帧显示时长（毫秒）。静态图为 0；GIF 动画按帧携带
    pub delay_ms: u32,
}

/// 统一的栅格图像（单帧或多帧动画）。
#[derive(Debug, Clone)]
pub struct RasterImage {
    pub width: u32,
    pub height: u32,
    /// 帧序列，至少包含一帧
    pub frames: Vec<Frame>,
}

impl RasterImage {
    /// 用单帧构建静态图。
    pub fn from_image(pixels: RgbaImage) -> Self {
        let (width, height) = (pixels.width(), pixels.height());
        Self {
            width,
            height,
            frames: vec![Frame {
                pixels,
                delay_ms: 0,
            }],
        }
    }

    /// 用多帧构建动画图。
    ///
    /// 边界处理：空帧列表会退化为 1x1 透明图，避免后续按索引取帧时 panic。
    pub fn from_frames(width: u32, height: u32, frames: Vec<Frame>) -> Self {
        if frames.is_empty() {
            return Self::from_image(RgbaImage::from_pixel(
                1,
                1,
                Rgba([0, 0, 0, 0]),
            ));
        }
        Self {
            width,
            height,
            frames,
        }
    }

    /// 帧数量。
    pub fn frame_count(&self) -> usize {
        self.frames.len()
    }

    /// 是否为动画（多于 1 帧）。
    pub fn is_animated(&self) -> bool {
        self.frames.len() > 1
    }

    /// 取第一帧像素。构造时已保证至少一帧，故此处不会越界。
    pub fn first(&self) -> &RgbaImage {
        &self.frames[0].pixels
    }

    /// 是否含有任意非完全不透明的像素。
    ///
    /// 用于判断输出到不支持 alpha 的格式（如 JPEG）时是否需要做背景压平。
    /// 采样步长复用为 1，逐像素判断以保证准确；大图由调用方决定是否调用。
    pub fn has_transparency(&self) -> bool {
        self.first().pixels().any(|p| p.0[3] < 255)
    }

    /// 把带 alpha 的图压平到指定底色上，输出三通道图。
    ///
    /// 用于 JPEG / BMP 这类不支持透明通道的格式，避免透明区域被写成黑块。
    /// 公式：out = src * a + bg * (1 - a)，`a` 取自像素自身 alpha。
    pub fn flatten_onto(&self, bg: [u8; 3]) -> image::RgbImage {
        let src = self.first();
        let mut out = image::RgbImage::new(self.width, self.height);
        for (dst_px, src_px) in out.pixels_mut().zip(src.pixels()) {
            let a = src_px.0[3] as u32;
            // 完全不透明直接取原色，避免无谓的浮点运算
            if a == 255 {
                dst_px.0 = [src_px.0[0], src_px.0[1], src_px.0[2]];
                continue;
            }
            if a == 0 {
                dst_px.0 = bg;
                continue;
            }
            let inv = 255 - a;
            dst_px.0 = [
                ((src_px.0[0] as u32 * a + bg[0] as u32 * inv) / 255) as u8,
                ((src_px.0[1] as u32 * a + bg[1] as u32 * inv) / 255) as u8,
                ((src_px.0[2] as u32 * a + bg[2] as u32 * inv) / 255) as u8,
            ];
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 单帧构造与帧查询() {
        let img = RasterImage::from_image(RgbaImage::from_pixel(4, 3, Rgba([1, 2, 3, 255])));
        assert_eq!((img.width, img.height), (4, 3));
        assert_eq!(img.frame_count(), 1);
        assert!(!img.is_animated());
    }

    #[test]
    fn 空帧列表退化为占位图而不panic() {
        let img = RasterImage::from_frames(10, 10, vec![]);
        assert_eq!(img.frame_count(), 1);
        // 占位图为 1x1 全透明，保证后续 first() 安全
        assert_eq!(img.first().get_pixel(0, 0).0, [0, 0, 0, 0]);
    }

    #[test]
    fn 透明检测与底色压平() {
        let mut pixels = RgbaImage::new(2, 1);
        pixels.put_pixel(0, 0, Rgba([255, 0, 0, 255])); // 不透明红
        pixels.put_pixel(1, 0, Rgba([0, 0, 255, 0])); // 全透明蓝
        let img = RasterImage::from_image(pixels);
        assert!(img.has_transparency());

        // 压平到白底：透明像素应变为白色，而非保留蓝色或变黑
        let flat = img.flatten_onto([255, 255, 255]);
        assert_eq!(flat.get_pixel(0, 0).0, [255, 0, 0]);
        assert_eq!(flat.get_pixel(1, 0).0, [255, 255, 255]);
    }

    #[test]
    fn 半透明像素按比例混合() {
        let mut pixels = RgbaImage::new(1, 1);
        // 50% 透明度的黑，压平到白底应得到中灰
        pixels.put_pixel(0, 0, Rgba([0, 0, 0, 128]));
        let img = RasterImage::from_image(pixels);
        let flat = img.flatten_onto([255, 255, 255]);
        let v = flat.get_pixel(0, 0).0[0];
        assert!((126..=129).contains(&v), "期望约 127，实际 {v}");
    }
}
