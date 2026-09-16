//! 图片格式识别与能力描述。
//!
//! 识别策略：**先看内容魔数，再看扩展名**。仅凭扩展名判断在真实场景中经常出错
//! （用户会把 PNG 改名成 .jpg 上传），而魔数判断对位图可靠。
//! SVG 是文本格式、没有固定魔数，用「文本特征匹配」兜底。

use crate::core::error::{PicProError, Result};

/// 内核支持的图片格式。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ImageFormat {
    Png,
    Jpeg,
    Gif,
    WebP,
    Bmp,
    Tiff,
    /// 矢量图，处理前需先栅格化
    Svg,
}

impl ImageFormat {
    /// 从文件扩展名推断格式（不区分大小写，允许带点前缀）。
    pub fn from_extension(ext: &str) -> Option<Self> {
        let e = ext.trim_start_matches('.').to_ascii_lowercase();
        match e.as_str() {
            "png" => Some(Self::Png),
            // jpg 与 jpeg 是同一种格式的两种扩展名
            "jpg" | "jpeg" | "jpe" => Some(Self::Jpeg),
            "gif" => Some(Self::Gif),
            "webp" => Some(Self::WebP),
            "bmp" => Some(Self::Bmp),
            "tif" | "tiff" => Some(Self::Tiff),
            "svg" => Some(Self::Svg),
            _ => None,
        }
    }

    /// 通过魔数识别格式。返回 None 表示不是已知的位图格式。
    pub fn from_magic(bytes: &[u8]) -> Option<Self> {
        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if bytes.starts_with(&[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]) {
            return Some(Self::Png);
        }
        // JPEG: FF D8 FF
        if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
            return Some(Self::Jpeg);
        }
        // GIF: "GIF87a" / "GIF89a"
        if bytes.starts_with(b"GIF87a") || bytes.starts_with(b"GIF89a") {
            return Some(Self::Gif);
        }
        // WebP: "RIFF" + 4 字节长度 + "WEBP"
        if bytes.len() >= 12 && bytes.starts_with(b"RIFF") && &bytes[8..12] == b"WEBP" {
            return Some(Self::WebP);
        }
        // BMP: "BM"
        if bytes.starts_with(b"BM") {
            return Some(Self::Bmp);
        }
        // TIFF: 小端 "II*\0" 或大端 "MM\0*"
        if bytes.starts_with(&[b'I', b'I', 0x2A, 0x00]) || bytes.starts_with(&[b'M', b'M', 0x00, 0x2A])
        {
            return Some(Self::Tiff);
        }
        None
    }

    /// 通过文本特征识别 SVG。
    ///
    /// SVG 没有魔数，且可能带 XML 声明、注释、DOCTYPE，因此在前若干字节里
    /// 查找 `<svg` 标签即可判为 SVG。为避免把普通文本误判，同时要求出现
    /// XML 风格尖括号结构。
    fn looks_like_svg(bytes: &[u8]) -> bool {
        // 只检查文件头部的有限字节，避免大文件全量扫描
        let head_len = bytes.len().min(4096);
        let head = &bytes[..head_len];
        // SVG 必然是文本。截断可能切在多字节字符中间，故用有损解码而非严格解析
        let text = String::from_utf8_lossy(head).to_ascii_lowercase();
        // 允许 XML 声明、注释、DOCTYPE 出现在 <svg 之前，因此直接查找标签
        text.contains("<svg")
    }

    /// 综合识别：内容优先，扩展名兜底。
    ///
    /// `filename` 可为 None（剪贴板等场景没有文件名）。
    pub fn detect(bytes: &[u8], filename: Option<&str>) -> Result<Self> {
        if bytes.is_empty() {
            return Err(PicProError::UnknownFormat("内容为空".into()));
        }
        // 1) 位图魔数
        if let Some(f) = Self::from_magic(bytes) {
            return Ok(f);
        }
        // 2) SVG 文本特征
        if Self::looks_like_svg(bytes) {
            return Ok(Self::Svg);
        }
        // 3) 魔数失败时才看扩展名（例如某些 TIFF 变体魔数不标准）
        if let Some(name) = filename {
            if let Some(ext) = std::path::Path::new(name).extension().and_then(|e| e.to_str()) {
                if let Some(f) = Self::from_extension(ext) {
                    return Ok(f);
                }
            }
        }
        Err(PicProError::UnknownFormat(format!(
            "前 {} 字节不匹配任何已知格式特征",
            bytes.len().min(16)
        )))
    }

    /// 写盘时使用的标准扩展名。
    pub fn extension(&self) -> &'static str {
        match self {
            Self::Png => "png",
            Self::Jpeg => "jpg",
            Self::Gif => "gif",
            Self::WebP => "webp",
            Self::Bmp => "bmp",
            Self::Tiff => "tiff",
            Self::Svg => "svg",
        }
    }

    /// 展示用名称。
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Png => "PNG",
            Self::Jpeg => "JPEG",
            Self::Gif => "GIF",
            Self::WebP => "WebP",
            Self::Bmp => "BMP",
            Self::Tiff => "TIFF",
            Self::Svg => "SVG",
        }
    }

    /// 是否为矢量格式（处理前需要栅格化）。
    pub fn is_vector(&self) -> bool {
        matches!(self, Self::Svg)
    }

    /// 是否支持多帧动画。
    pub fn supports_animation(&self) -> bool {
        matches!(self, Self::Gif | Self::WebP)
    }

    /// 是否能承载 alpha 透明通道。
    pub fn supports_alpha(&self) -> bool {
        // JPEG 与 BMP 均无 alpha；TIFF/GIF/PNG/WebP 可以
        matches!(self, Self::Png | Self::Gif | Self::WebP | Self::Tiff)
    }

    /// 是否支持有损质量参数。
    ///
    /// 注意：`image` crate 的 WebP 编码器只提供无损编码
    /// （`WebPEncoder::new_lossless`），因此 WebP 不参与质量搜索，
    /// 其体积控制只能靠调整分辨率实现。
    pub fn supports_quality(&self) -> bool {
        matches!(self, Self::Jpeg)
    }

    /// 输出该格式时的候选格式列表（供界面「改格式」下拉使用）。
    pub fn all_output_formats() -> &'static [ImageFormat] {
        &[
            Self::Png,
            Self::Jpeg,
            Self::Gif,
            Self::WebP,
            Self::Bmp,
            Self::Tiff,
        ]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 扩展名识别覆盖大小写与点前缀() {
        assert_eq!(ImageFormat::from_extension("PNG"), Some(ImageFormat::Png));
        assert_eq!(ImageFormat::from_extension(".JpEg"), Some(ImageFormat::Jpeg));
        assert_eq!(ImageFormat::from_extension("svg"), Some(ImageFormat::Svg));
        assert_eq!(ImageFormat::from_extension("heic"), None);
    }

    #[test]
    fn 魔数优先于扩展名() {
        // 内容为 PNG，但文件名谎称 .jpg，应以内容为准
        let png_head = [0x89u8, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0];
        assert_eq!(
            ImageFormat::detect(&png_head, Some("伪装.jpg")).unwrap(),
            ImageFormat::Png
        );
    }

    #[test]
    fn 识别常见位图魔数() {
        assert_eq!(
            ImageFormat::from_magic(&[0xFF, 0xD8, 0xFF, 0xE0]),
            Some(ImageFormat::Jpeg)
        );
        assert_eq!(ImageFormat::from_magic(b"GIF89a....."), Some(ImageFormat::Gif));
        assert_eq!(ImageFormat::from_magic(b"BM\x00\x00"), Some(ImageFormat::Bmp));
        let mut riff = b"RIFF".to_vec();
        riff.extend_from_slice(&[0, 0, 0, 0]);
        riff.extend_from_slice(b"WEBP");
        assert_eq!(ImageFormat::from_magic(&riff), Some(ImageFormat::WebP));
    }

    #[test]
    fn 识别svg文本() {
        let svg = br#"<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"/>"#;
        assert_eq!(ImageFormat::detect(svg, None).unwrap(), ImageFormat::Svg);
        // 带注释与换行也应识别
        let svg2 = b"<!-- comment -->\n<SVG width=\"10\"/>";
        assert_eq!(ImageFormat::detect(svg2, None).unwrap(), ImageFormat::Svg);
    }

    #[test]
    fn 无法识别时报错() {
        let junk = b"this is not an image at all";
        let r = ImageFormat::detect(junk, Some("a.txt"));
        assert!(matches!(r, Err(PicProError::UnknownFormat(_))));
    }

    #[test]
    fn 能力标记符合预期() {
        assert!(ImageFormat::Jpeg.supports_quality());
        // WebP 编码器仅支持无损，不应参与质量搜索
        assert!(!ImageFormat::WebP.supports_quality());
        assert!(!ImageFormat::Jpeg.supports_alpha());
        assert!(ImageFormat::Gif.supports_animation());
        assert!(ImageFormat::Svg.is_vector());
        // SVG 不应出现在输出格式候选里（位图无法反向矢量化）
        assert!(!ImageFormat::all_output_formats().contains(&ImageFormat::Svg));
    }
}
