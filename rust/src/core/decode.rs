//! 解码层：把各种输入格式统一解成 [`RasterImage`]。
//!
//! 三类输入的处理方式不同：
//! - **普通位图**（png/jpg/jpeg/webp/bmp/tiff）：直接交给 `image` 解码，单帧输出；
//! - **GIF**：走 `AnimationDecoder` 逐帧解码，保留动画与帧延时；
//! - **SVG**：矢量图，用 resvg 按目标尺寸栅格化，得到单帧位图。
//!
//! 一个易错点：tiny-skia 的像素缓冲是**预乘 alpha**，而 `image` 全程使用直通 alpha，
//! 因此 SVG 渲染结果必须做反预乘，否则半透明区域颜色会整体偏亮。

use std::io::Cursor;

use image::codecs::gif::GifDecoder;
use image::{AnimationDecoder, Rgba, RgbaImage};

use crate::core::error::{PicProError, Result};
use crate::core::format::ImageFormat;
use crate::core::types::{Frame, RasterImage};

/// 解码参数。
#[derive(Debug, Clone)]
pub struct DecodeOptions {
    /// SVG 栅格化的目标宽度（像素）。None 表示按 SVG 自带尺寸渲染。
    pub svg_target_width: Option<u32>,
    /// SVG 栅格化的目标高度。与宽度同时给出时会拉伸到该尺寸。
    pub svg_target_height: Option<u32>,
    /// SVG 自带尺寸缺失时的兜底边长。
    pub svg_default_size: u32,
    /// 是否解码 GIF 的全部帧。为 false 时只取首帧（用于换背景等不支持动画的操作）
    pub decode_all_frames: bool,
}

impl Default for DecodeOptions {
    fn default() -> Self {
        Self {
            svg_target_width: None,
            svg_target_height: None,
            svg_default_size: 1024,
            decode_all_frames: true,
        }
    }
}

/// 解码结果：图像 + 实际识别出的源格式（供上游决定输出默认格式等）。
pub struct DecodedImage {
    pub image: RasterImage,
    pub source_format: ImageFormat,
}

/// 从文件路径解码。
pub fn decode_file(path: &str, opts: &DecodeOptions) -> Result<DecodedImage> {
    let bytes = std::fs::read(path)?;
    // 传入文件名，便于魔数识别失败时用扩展名兜底
    decode_bytes(&bytes, Some(path), opts)
}

/// 从内存字节解码。
pub fn decode_bytes(bytes: &[u8], filename: Option<&str>, opts: &DecodeOptions) -> Result<DecodedImage> {
    let source_format = ImageFormat::detect(bytes, filename)?;
    let image = match source_format {
        ImageFormat::Svg => decode_svg(bytes, opts)?,
        ImageFormat::Gif => decode_gif(bytes, opts)?,
        // 其余位图共用同一条路径
        _ => decode_static(bytes)?,
    };
    Ok(DecodedImage {
        image,
        source_format,
    })
}

/// 解码普通静态位图（只取首帧）。
fn decode_static(bytes: &[u8]) -> Result<RasterImage> {
    let img = image::load_from_memory(bytes)?;
    // 统一转 RGBA8，后续处理只面对一种像素布局
    Ok(RasterImage::from_image(img.to_rgba8()))
}

/// 解码 GIF：保留动画帧与帧延时。
///
/// `image` 的 GIF 解码器内部维护整幅画布并处理 disposal，
/// 因此每帧返回的都是**完整画布尺寸**的 RGBA8，无需再做偏移合成。
fn decode_gif(bytes: &[u8], opts: &DecodeOptions) -> Result<RasterImage> {
    let decoder = GifDecoder::new(Cursor::new(bytes))
        .map_err(|e| PicProError::Decode(format!("GIF 解码器初始化失败：{e}")))?;

    let frames = decoder
        .into_frames()
        .collect_frames()
        .map_err(|e| PicProError::Decode(format!("GIF 逐帧解码失败：{e}")))?;

    if frames.is_empty() {
        return Err(PicProError::Decode("GIF 不含任何帧".into()));
    }

    // 只取首帧时直接返回，避免大动画的无谓内存占用
    if !opts.decode_all_frames {
        let first = frames.into_iter().next().expect("已确认非空");
        return Ok(RasterImage::from_image(first.into_buffer()));
    }

    let (w, h) = {
        let b = frames[0].buffer();
        (b.width(), b.height())
    };

    let frames = frames
        .into_iter()
        .map(|f| {
            // GIF 帧延时的单位是 10ms，numerator/denominator 由库换算
            let (num, den) = f.delay().numer_denom_ms();
            let delay_ms = if den == 0 { 0 } else { num / den };
            Frame {
                pixels: f.into_buffer(),
                delay_ms,
            }
        })
        .collect();

    Ok(RasterImage::from_frames(w, h, frames))
}

/// 用 resvg 把 SVG 栅格化为 RGBA 位图。
///
/// 尺寸策略：
/// - 同时给了目标宽高 → 拉伸到该尺寸；
/// - 只给宽度 → 按原始宽高比等比缩放；
/// - 都没给 → 用 SVG 自带尺寸；自带尺寸缺失/为 0 时用 `svg_default_size` 兜底。
fn decode_svg(bytes: &[u8], opts: &DecodeOptions) -> Result<RasterImage> {
    let tree = resvg::usvg::Tree::from_data(bytes, &resvg::usvg::Options::default())
        .map_err(|e| PicProError::Svg(format!("SVG 解析失败：{e}")))?;

    let size = tree.size();
    let (mut src_w, mut src_h) = (size.width(), size.height());

    // 自带尺寸无效时用兜底值，避免后续除零
    if !(src_w > 0.0) || !(src_h > 0.0) {
        src_w = opts.svg_default_size as f32;
        src_h = opts.svg_default_size as f32;
    }

    // 计算目标像素尺寸
    let (tw, th) = match (opts.svg_target_width, opts.svg_target_height) {
        (Some(w), Some(h)) => (w.max(1), h.max(1)),
        (Some(w), None) => {
            // 等比：高度按原始宽高比推导
            let ratio = src_h / src_w;
            (w.max(1), (w as f32 * ratio).round().max(1.0) as u32)
        }
        (None, Some(h)) => {
            let ratio = src_w / src_h;
            ((h as f32 * ratio).round().max(1.0) as u32, h.max(1))
        }
        (None, None) => (src_w.round().max(1.0) as u32, src_h.round().max(1.0) as u32),
    };

    let mut pixmap = resvg::tiny_skia::Pixmap::new(tw, th)
        .ok_or_else(|| PicProError::Svg(format!("无法分配 {tw}x{th} 的渲染画布")))?;

    // 按目标与原始尺寸之比做整体缩放
    let sx = tw as f32 / src_w;
    let sy = th as f32 / src_h;
    resvg::render(
        &tree,
        resvg::tiny_skia::Transform::from_scale(sx, sy),
        &mut pixmap.as_mut(),
    );

    // tiny-skia 输出为预乘 alpha，必须反预乘转回直通 alpha
    let mut buf = pixmap.take();
    unpremultiply_in_place(&mut buf);

    let rgba = RgbaImage::from_raw(tw, th, buf)
        .ok_or_else(|| PicProError::Svg("渲染缓冲尺寸与画布不一致".into()))?;
    Ok(RasterImage::from_image(rgba))
}

/// 就地反预乘：把 tiny-skia 的预乘 RGBA 转成直通 RGBA。
///
/// 边界处理：alpha 为 0 时像素本身无意义，直接置零避免除零；
/// alpha 为 255 时无需换算。
pub(crate) fn unpremultiply_in_place(buf: &mut [u8]) {
    for px in buf.chunks_exact_mut(4) {
        let a = px[3];
        if a == 255 {
            continue;
        }
        if a == 0 {
            px[0] = 0;
            px[1] = 0;
            px[2] = 0;
            continue;
        }
        let a32 = a as u32;
        // 加 a/2 做四舍五入，再取 min 防止结果溢出 255
        px[0] = (((px[0] as u32 * 255) + a32 / 2) / a32).min(255) as u8;
        px[1] = (((px[1] as u32 * 255) + a32 / 2) / a32).min(255) as u8;
        px[2] = (((px[2] as u32 * 255) + a32 / 2) / a32).min(255) as u8;
    }
}

/// 生成一张纯色底图（用于「无输入仅生成」等场景与测试）。
pub fn solid_image(width: u32, height: u32, color: [u8; 4]) -> RasterImage {
    RasterImage::from_image(RgbaImage::from_pixel(
        width.max(1),
        height.max(1),
        Rgba(color),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 反预乘还原直通alpha() {
        // 50% 透明度的纯白，预乘后各通道为 128
        let mut buf = vec![128u8, 128, 128, 128];
        unpremultiply_in_place(&mut buf);
        assert_eq!(buf[3], 128);
        // 反预乘应把 RGB 拉回约 255
        assert!(buf[0] >= 254, "期望约 255，实际 {}", buf[0]);
    }

    #[test]
    fn 反预乘处理全透明与不透明边界() {
        // 全透明像素不得除零，直接置零
        let mut buf = vec![10u8, 20, 30, 0];
        unpremultiply_in_place(&mut buf);
        assert_eq!(buf, vec![0, 0, 0, 0]);
        // 不透明像素保持原值
        let mut buf2 = vec![10u8, 20, 30, 255];
        unpremultiply_in_place(&mut buf2);
        assert_eq!(buf2, vec![10, 20, 30, 255]);
    }

    #[test]
    fn 解码png并按魔数识别() {
        // 用编码器生成一张真实 PNG，再走完整解码路径，验证格式识别与解码联通
        let img = RgbaImage::from_pixel(3, 2, Rgba([12, 34, 56, 255]));
        let mut png = Vec::new();
        image::DynamicImage::ImageRgba8(img)
            .write_to(&mut Cursor::new(&mut png), image::ImageFormat::Png)
            .unwrap();

        let out = decode_bytes(&png, None, &DecodeOptions::default()).unwrap();
        assert_eq!(out.source_format, ImageFormat::Png);
        assert_eq!((out.image.width, out.image.height), (3, 2));
        assert_eq!(out.image.first().get_pixel(0, 0).0, [12, 34, 56, 255]);
    }

    #[test]
    fn 解码svg得到直通alpha且尺寸可指定() {
        // 红色矩形覆盖左半，右半透明；用于验证栅格化尺寸与 alpha 保真。
        // 注意外层用 r##"…"##：内容里的 `fill="#FF0000"` 含 `"#`，
        // 若只用 r#"…"# 会被提前截断。
        let svg = br##"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 10 10">
            <rect x="0" y="0" width="5" height="10" fill="#FF0000"/>
        </svg>"##;
        let opts = DecodeOptions {
            svg_target_width: Some(40),
            svg_target_height: Some(40),
            ..Default::default()
        };
        let out = decode_bytes(svg, None, &opts).unwrap();
        assert_eq!(out.source_format, ImageFormat::Svg);
        assert_eq!((out.image.width, out.image.height), (40, 40));

        // 左半为不透明红
        let left = out.image.first().get_pixel(5, 20).0;
        assert_eq!(left[3], 255, "左半应不透明");
        assert!(left[0] > 200, "左半应为红色，实际 {left:?}");
        // 右半为全透明
        let right = out.image.first().get_pixel(35, 20).0;
        assert_eq!(right[3], 0, "右半应透明，实际 {right:?}");
    }

    #[test]
    fn 空输入报错而非panic() {
        let r = decode_bytes(&[], None, &DecodeOptions::default());
        assert!(matches!(r, Err(PicProError::UnknownFormat(_))));
    }
}
