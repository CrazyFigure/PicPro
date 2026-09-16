//! 编码层：把 [`RasterImage`] 输出为指定格式的字节流。
//!
//! 各格式的能力差异很大，必须分别处理：
//!
//! | 格式 | 质量参数 | 透明通道 | 动画 || 备注 |
//! |------|---------|---------|------|------|
//! | JPEG | 有 | 无 | 否 | 用 `jpeg-encoder` 以获得色度抽样控制权 |
//! | PNG  | 无（有压缩级别） | 有 | 仅首帧 | 标准库不支持 APNG 写出 |
//! | WebP | 无（仅无损） | 有 | 仅首帧 | `image` 只提供无损编码 |
//! | GIF  | 无（有量化速度） | 1 位 | **有** | 保留动画 |
//! | BMP  | 无 | 无 | 否 | |
//! | TIFF | 无 | 有 | 仅首帧 | |
//!
//! 因此：**输出不支持动画的格式时，动画图只取首帧**；
//! 输出不支持 alpha 的格式时，先把图压平到指定底色，避免透明区变黑块。

use std::io::Cursor;

use image::codecs::bmp::BmpEncoder;
use image::codecs::gif::{GifEncoder, Repeat};
use image::codecs::png::{CompressionType, FilterType, PngEncoder};
use image::codecs::tiff::TiffEncoder;
use image::codecs::webp::WebPEncoder;
use image::{ExtendedColorType, ImageEncoder};

use crate::core::error::{PicProError, Result};
use crate::core::format::ImageFormat;
use crate::core::types::RasterImage;

/// 编码参数。
#[derive(Debug, Clone)]
pub struct EncodeOptions {
    pub format: ImageFormat,
    /// 有损质量，1~100。仅 JPEG 使用。
    pub quality: u8,
    /// JPEG 是否使用 4:4:4 色度抽样。
    ///
    /// 默认开启：4:2:0 会丢弃一半色度分辨率，在证件照发丝、彩色文字边缘
    /// 会产生肉眼可见的色彩锯齿。体积敏感且画面以大面积平滑色块为主时
    /// 可关闭以换取更小体积。
    pub jpeg_no_chroma_subsampling: bool,
    /// JPEG 是否输出渐进式（网络加载时逐层显示，体积略小）
    pub jpeg_progressive: bool,
    /// JPEG 是否优化霍夫曼表（体积可再减约 3~5%）
    pub jpeg_optimize_huffman: bool,
    /// 输出格式不支持 alpha 时的压平底色。
    ///
    /// 默认白色：证件照、产品图等场景的白底占绝对多数，比黑色安全。
    pub flatten_background: [u8; 3],
    /// GIF 量化速度，1（最慢最优）~30（最快最差）。
    ///
    /// 默认 10：批量处理场景下速度与质量的折中，1 在大动图上会非常慢。
    pub gif_speed: i32,
    /// GIF 是否无限循环
    pub gif_loop_forever: bool,
    /// PNG 是否使用最高压缩级别（更慢但更小）
    pub png_best_compression: bool,
}

impl Default for EncodeOptions {
    fn default() -> Self {
        Self {
            format: ImageFormat::Jpeg,
            quality: 90,
            jpeg_no_chroma_subsampling: true,
            jpeg_progressive: true,
            jpeg_optimize_huffman: true,
            flatten_background: [255, 255, 255],
            gif_speed: 10,
            gif_loop_forever: true,
            png_best_compression: true,
        }
    }
}

impl EncodeOptions {
    /// 指定格式并沿用其余默认值。
    pub fn for_format(format: ImageFormat) -> Self {
        Self {
            format,
            ..Default::default()
        }
    }
}

/// 编码为字节流。
pub fn encode(img: &RasterImage, opts: &EncodeOptions) -> Result<Vec<u8>> {
    match opts.format {
        ImageFormat::Jpeg => encode_jpeg(img, opts),
        ImageFormat::Png => encode_png(img, opts),
        ImageFormat::WebP => encode_webp(img, opts),
        ImageFormat::Gif => encode_gif(img, opts),
        ImageFormat::Bmp => encode_bmp(img, opts),
        ImageFormat::Tiff => encode_tiff(img),
        // SVG 无法由位图反向生成
        ImageFormat::Svg => Err(PicProError::UnsupportedFormat(
            "不支持把位图输出为 SVG（矢量图无法由像素反推）".into(),
        )),
    }
}

/// JPEG 编码。
///
/// 关键点：JPEG 无 alpha 通道，必须先压平到 `flatten_background`，
/// 否则透明区域会被当作黑色输出。
fn encode_jpeg(img: &RasterImage, opts: &EncodeOptions) -> Result<Vec<u8>> {
    // jpeg-encoder 的尺寸参数是 u16，超限必须显式报错而不是静默截断
    if img.width > u16::MAX as u32 || img.height > u16::MAX as u32 {
        return Err(PicProError::InvalidArgument(format!(
            "JPEG 宽高上限为 {}，当前为 {}x{}",
            u16::MAX,
            img.width,
            img.height
        )));
    }

    // 无透明像素时直接取原色，避免无谓的压平运算
    let flat = if img.has_transparency() {
        let rgb = img.flatten_onto(opts.flatten_background);
        rgb.into_raw()
    } else {
        let src = img.first();
        let mut buf = Vec::with_capacity((img.width * img.height * 3) as usize);
        for px in src.pixels() {
            buf.extend_from_slice(&px.0[..3]);
        }
        buf
    };

    let mut out = Vec::new();
    let mut enc = jpeg_encoder::Encoder::new(&mut out, opts.quality.clamp(1, 100));
    if opts.jpeg_no_chroma_subsampling {
        enc.set_sampling_factor(jpeg_encoder::SamplingFactor::F_1_1);
    }
    enc.set_progressive(opts.jpeg_progressive);
    enc.set_optimized_huffman_tables(opts.jpeg_optimize_huffman);
    enc.encode(
        &flat,
        img.width as u16,
        img.height as u16,
        jpeg_encoder::ColorType::Rgb,
    )
    .map_err(|e| PicProError::Encode(format!("JPEG 编码失败：{e}")))?;
    Ok(out)
}

/// PNG 编码（只输出首帧，标准库不支持 APNG 写出）。
///
/// 无透明像素时降为三通道输出，可明显减小体积。
fn encode_png(img: &RasterImage, opts: &EncodeOptions) -> Result<Vec<u8>> {
    let compression = if opts.png_best_compression {
        CompressionType::Best
    } else {
        CompressionType::Fast
    };
    let mut out = Vec::new();
    let enc = PngEncoder::new_with_quality(&mut out, compression, FilterType::Adaptive);
    let has_alpha = img.has_transparency();

    if has_alpha {
        enc.write_image(
            img.first().as_raw(),
            img.width,
            img.height,
            ExtendedColorType::Rgba8,
        )?;
    } else {
        enc.write_image(
            &strip_alpha(img),
            img.width,
            img.height,
            ExtendedColorType::Rgb8,
        )?;
    }
    Ok(out)
}

/// WebP 编码（无损；只输出首帧）。
///
/// 说明：`image` crate 仅提供无损 WebP 编码器，因此 WebP 没有质量维度，
/// 其编码参数只取决于像素类型（有无 alpha），`opts` 中的质量设置对它无效。
/// 体积只能通过降低分辨率来控制，这一点在压缩逻辑中有对应分支。
fn encode_webp(img: &RasterImage, _opts: &EncodeOptions) -> Result<Vec<u8>> {
    let mut out = Vec::new();
    if img.has_transparency() {
        WebPEncoder::new_lossless(&mut out).write_image(
            img.first().as_raw(),
            img.width,
            img.height,
            ExtendedColorType::Rgba8,
        )?;
    } else {
        WebPEncoder::new_lossless(&mut out).write_image(
            &strip_alpha(img),
            img.width,
            img.height,
            ExtendedColorType::Rgb8,
        )?;
    }
    // 无损编码失败时保留明确错误，避免返回空字节流被误当作成功
    if out.is_empty() {
        return Err(PicProError::Encode("WebP 无损编码输出为空".into()));
    }
    Ok(out)
}

/// GIF 编码，**保留动画**。
///
/// 注意：GIF 的帧延时单位为 10ms，且过小的延时会因取整变成 0，
/// 被多数查看器当作「按默认速度播放」；这里把下限钳到 20ms。
fn encode_gif(img: &RasterImage, opts: &EncodeOptions) -> Result<Vec<u8>> {
    let mut out = Vec::new();
    {
        let mut enc = GifEncoder::new_with_speed(&mut out, opts.gif_speed.clamp(1, 30));
        enc.set_repeat(if opts.gif_loop_forever {
            Repeat::Infinite
        } else {
            Repeat::Finite(0)
        })
        .map_err(|e| PicProError::Encode(format!("设置 GIF 循环失败：{e}")))?;

        let frames = img.frames.iter().map(|f| {
            let delay = image::Delay::from_numer_denom_ms(f.delay_ms.max(20), 1);
            // left/top 恒为 0：内核内部所有帧都已是整幅画布尺寸
            image::Frame::from_parts(f.pixels.clone(), 0, 0, delay)
        });
        enc.encode_frames(frames)
            .map_err(|e| PicProError::Encode(format!("GIF 编码失败：{e}")))?;
    }
    Ok(out)
}

/// BMP 编码（无 alpha，需压平）。
fn encode_bmp(img: &RasterImage, opts: &EncodeOptions) -> Result<Vec<u8>> {
    let mut out = Vec::new();
    BmpEncoder::new(&mut out).write_image(
        &img.flatten_onto(opts.flatten_background).into_raw(),
        img.width,
        img.height,
        ExtendedColorType::Rgb8,
    )?;
    Ok(out)
}

/// TIFF 编码（保留 alpha，只输出首帧）。
///
/// TIFF 编码器要求输出目标同时实现 `Write + Seek`，
/// 因此不能直接写 `Vec<u8>`，需经 `Cursor` 中转后再取出缓冲。
fn encode_tiff(img: &RasterImage) -> Result<Vec<u8>> {
    let mut cursor = Cursor::new(Vec::<u8>::new());
    if img.has_transparency() {
        TiffEncoder::new(&mut cursor).write_image(
            img.first().as_raw(),
            img.width,
            img.height,
            ExtendedColorType::Rgba8,
        )?;
    } else {
        TiffEncoder::new(&mut cursor).write_image(
            &strip_alpha(img),
            img.width,
            img.height,
            ExtendedColorType::Rgb8,
        )?;
    }
    Ok(cursor.into_inner())
}

/// 去掉 alpha 通道，得到 RGB 字节流（用于无透明像素的图，可减小输出体积）。
fn strip_alpha(img: &RasterImage) -> Vec<u8> {
    let src = img.first();
    let mut buf = Vec::with_capacity((img.width * img.height * 3) as usize);
    for px in src.pixels() {
        buf.extend_from_slice(&px.0[..3]);
    }
    buf
}

/// 便捷函数：按指定格式以默认参数编码。
pub fn encode_as(img: &RasterImage, format: ImageFormat, quality: u8) -> Result<Vec<u8>> {
    encode(
        img,
        &EncodeOptions {
            format,
            quality,
            ..Default::default()
        },
    )
}

/// 把编码结果写盘，返回写入字节数。
pub fn encode_to_file(img: &RasterImage, path: &str, opts: &EncodeOptions) -> Result<usize> {
    let bytes = encode(img, opts)?;
    // 确保父目录存在，避免因目录缺失导致整批任务失败
    if let Some(parent) = std::path::Path::new(path).parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)?;
        }
    }
    std::fs::write(path, &bytes)?;
    Ok(bytes.len())
}

/// 调试辅助：把编码结果重新解码，用于测试中验证往返一致性。
#[cfg(test)]
fn roundtrip(img: &RasterImage, opts: &EncodeOptions) -> RasterImage {
    let bytes = encode(img, opts).expect("编码应成功");
    let dec = image::load_from_memory(&bytes).expect("解码应成功");
    RasterImage::from_image(dec.to_rgba8())
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{Rgba, RgbaImage};

    /// 构造一张纯色测试图
    fn solid(w: u32, h: u32, c: [u8; 4]) -> RasterImage {
        RasterImage::from_image(RgbaImage::from_pixel(w, h, Rgba(c)))
    }

    #[test]
    fn jpeg编码可被解码回且尺寸一致() {
        let img = solid(64, 48, [200, 30, 40, 255]);
        let out = roundtrip(&img, &EncodeOptions::for_format(ImageFormat::Jpeg));
        assert_eq!((out.width, out.height), (64, 48));
        // JPEG 有损，允许少量色差
        let px = out.first().get_pixel(32, 24).0;
        assert!((px[0] as i32 - 200).abs() < 20, "R 偏差过大：{px:?}");
        assert!(px[3] == 255, "JPEG 输出应完全不透明");
    }

    #[test]
    fn jpeg对透明图先压平到白底而非变黑() {
        // 全透明图输出为 JPEG，应得到白色而非黑色
        let img = solid(16, 16, [0, 0, 0, 0]);
        let opts = EncodeOptions {
            format: ImageFormat::Jpeg,
            flatten_background: [255, 255, 255],
            ..Default::default()
        };
        let out = roundtrip(&img, &opts);
        let px = out.first().get_pixel(8, 8).0;
        assert!(px[0] > 230, "压平到白底后应接近白色，实际 {px:?}");
    }

    #[test]
    fn png保留alpha且无透明时降为三通道() {
        // 含透明像素：应保留 alpha
        let mut px = RgbaImage::new(8, 8);
        px.put_pixel(0, 0, Rgba([255, 0, 0, 0]));
        let img = RasterImage::from_image(px);
        let bytes = encode_as(&img, ImageFormat::Png, 90).unwrap();
        let dec = image::load_from_memory(&bytes).unwrap().to_rgba8();
        assert_eq!(dec.get_pixel(0, 0).0[3], 0, "PNG 应保留透明通道");

        // 全不透明图：应降为三通道以省体积
        let opaque = solid(64, 64, [10, 20, 30, 255]);
        let bytes2 = encode_as(&opaque, ImageFormat::Png, 90).unwrap();
        let dec2 = image::load_from_memory(&bytes2).unwrap();
        assert_eq!(
            dec2.color(),
            image::ColorType::Rgb8,
            "无透明像素时应输出 Rgb8"
        );
    }

    #[test]
    fn gif保留动画帧数与延时() {
        // 构造三帧动画，验证帧数与延时都能往返保留
        let mut frames = Vec::new();
        for i in 0..3u8 {
            let mut p = RgbaImage::new(10, 10);
            for y in 0..10 {
                for x in 0..10 {
                    p.put_pixel(x, y, Rgba([i * 80, 0, 0, 255]));
                }
            }
            frames.push(crate::core::types::Frame {
                pixels: p,
                delay_ms: 100,
            });
        }
        let img = RasterImage::from_frames(10, 10, frames);
        let bytes = encode_as(&img, ImageFormat::Gif, 90).unwrap();

        let dec = crate::core::decode::decode_bytes(
            &bytes,
            None,
            &crate::core::decode::DecodeOptions::default(),
        )
        .unwrap();
        assert_eq!(dec.source_format, ImageFormat::Gif);
        assert_eq!(dec.image.frame_count(), 3, "GIF 应保留三帧");
        assert!(dec.image.is_animated());
        assert_eq!(dec.image.frames[0].delay_ms, 100, "帧延时应保留");
    }

    #[test]
    fn 动画图输出静态格式时只取首帧而不报错() {
        let mut frames = Vec::new();
        for i in 0..3u8 {
            frames.push(crate::core::types::Frame {
                pixels: RgbaImage::from_pixel(10, 10, Rgba([i * 60, 10, 10, 255])),
                delay_ms: 100,
            });
        }
        let img = RasterImage::from_frames(10, 10, frames);
        // 输出 JPEG 不应报错，而是取首帧
        let bytes = encode_as(&img, ImageFormat::Jpeg, 90).unwrap();
        let dec = image::load_from_memory(&bytes).unwrap().to_rgba8();
        assert_eq!((dec.width(), dec.height()), (10, 10));
    }

    #[test]
    fn svg不能作为输出格式() {
        let img = solid(4, 4, [0, 0, 0, 255]);
        let r = encode_as(&img, ImageFormat::Svg, 90);
        assert!(matches!(r, Err(PicProError::UnsupportedFormat(_))));
    }

    #[test]
    fn webp无损编码可被解码回() {
        let img = solid(32, 32, [12, 200, 90, 255]);
        let bytes = encode_as(&img, ImageFormat::WebP, 90).unwrap();
        assert!(!bytes.is_empty());
        let dec = image::load_from_memory(&bytes).unwrap().to_rgba8();
        // 无损编码应精确还原颜色
        assert_eq!(dec.get_pixel(16, 16).0, [12, 200, 90, 255]);
    }

    #[test]
    fn bmp与tiff可正常写出() {
        let img = solid(16, 16, [1, 2, 3, 255]);
        assert!(!encode_as(&img, ImageFormat::Bmp, 90).unwrap().is_empty());
        assert!(!encode_as(&img, ImageFormat::Tiff, 90).unwrap().is_empty());
    }
}
