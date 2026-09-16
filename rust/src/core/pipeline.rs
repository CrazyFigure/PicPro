//! 完整处理流水线。
//!
//! 把「解码 → 裁剪 → 换背景 → 压缩 → 编码」串成一条可复用的流程，
//! 好处是这段逻辑可以脱离 FFI 单独测试，接口层只需做数据映射。
//!
//! **顺序不可颠倒**：证件照的体积要求是在规定像素下考核的，
//! 若先压体积再裁剪，裁完体积会变化，需要重新压缩。
//!
//! 另外流水线会收集 `notes` 与 `warnings`：
//! 前者是「做了什么」的事实说明（如检测到的背景色），
//! 后者是「可能不符合预期」的提醒（如动画帧被丢弃、质量未达下限），
//! 让界面能把算法的真实行为透明地告诉用户。

use crate::core::background::{replace_background, BackgroundOptions, BackgroundReport};
use crate::core::compress::{compress, CompressOptions};
use crate::core::crop::{crop, crop_to_exact_size, suggest_crop_rect, CropRect};
use crate::core::decode::{decode_bytes, decode_file, DecodeOptions};
use crate::core::encode::encode;
use crate::core::error::{PicProError, Result};
use crate::core::format::ImageFormat;
use crate::core::presets::find_preset;
use crate::core::types::RasterImage;

/// 裁剪参数。
#[derive(Debug, Clone, Default)]
pub struct CropSpec {
    /// 归一化裁剪框。None 表示不裁剪；有 `preset_id` 时表示按规格自动构图。
    pub rect: Option<CropRect>,
    /// 目标输出宽度。与 `out_height` 同时给出时缩放到精确像素。
    pub out_width: Option<u32>,
    /// 目标输出高度。
    pub out_height: Option<u32>,
    /// 证件照规格 id。给出时会覆盖输出像素为规格规定值。
    pub preset_id: Option<String>,
    /// 自动构图时的纵向锚点，默认 0.06（给头顶留少量余量）
    pub vertical_anchor: f32,
}

impl CropSpec {
    /// 是否完全不涉及裁剪。
    pub fn is_empty(&self) -> bool {
        self.rect.is_none()
            && self.out_width.is_none()
            && self.out_height.is_none()
            && self.preset_id.is_none()
    }
}

/// 流水线请求。
#[derive(Debug, Clone)]
pub struct PipelineRequest {
    /// 输入字节（三端通用）。与 `input_path` 二选一。
    pub input_bytes: Option<Vec<u8>>,
    /// 输入文件路径（仅原生端可用，可省去 Dart 侧读取）。
    pub input_path: Option<String>,
    /// 输入文件名，用于格式识别的扩展名兜底
    pub filename: Option<String>,
    pub crop: CropSpec,
    pub background: Option<BackgroundOptions>,
    pub compress: CompressOptions,
    /// 输出格式。None 表示按源格式推断。
    pub output_format: Option<ImageFormat>,
    pub decode: DecodeOptions,
}

impl Default for PipelineRequest {
    fn default() -> Self {
        Self {
            input_bytes: None,
            input_path: None,
            filename: None,
            crop: CropSpec::default(),
            background: None,
            compress: CompressOptions::default(),
            output_format: None,
            decode: DecodeOptions::default(),
        }
    }
}

/// 流水线输出。
#[derive(Debug, Clone)]
pub struct PipelineOutput {
    /// 最终字节流
    pub bytes: Vec<u8>,
    /// 输出像素尺寸
    pub width: u32,
    pub height: u32,
    /// 输出格式
    pub format: ImageFormat,
    /// 源格式（界面可据此提示「已从 X 转为 Y」）
    pub source_format: ImageFormat,
    /// 最终 JPEG 质量（非质量格式为其质量上限值）
    pub quality: u8,
    /// 最终缩放比例
    pub scale: f32,
    /// 换背景报告（未换背景时为 None）
    pub background: Option<BackgroundReport>,
    /// 做了什么的说明
    pub notes: Vec<String>,
    /// 需要提醒用户的降级行为
    pub warnings: Vec<String>,
}

/// 推断输出格式。
///
/// 规则：
/// - 用户显式指定则优先；
/// - SVG 源必须转位图（无法写出 SVG）；
/// - 其余情况沿用源格式，保持用户预期。
pub fn resolve_output_format(
    source: ImageFormat,
    requested: Option<ImageFormat>,
) -> Result<ImageFormat> {
    if let Some(f) = requested {
        if f == ImageFormat::Svg {
            return Err(PicProError::UnsupportedFormat(
                "无法输出 SVG：位图不能反向转换为矢量图".into(),
            ));
        }
        return Ok(f);
    }
    if source == ImageFormat::Svg {
        // SVG 栅格化后默认输出 PNG，可保留透明背景
        return Ok(ImageFormat::Png);
    }
    Ok(source)
}

/// 执行流水线。
pub fn run(req: &PipelineRequest) -> Result<PipelineOutput> {
    let mut notes: Vec<String> = Vec::new();
    let mut warnings: Vec<String> = Vec::new();

    // ---------- 步骤 1：解码 ----------
    let (mut img, source_format) = if let Some(bytes) = &req.input_bytes {
        let d = decode_bytes(bytes, req.filename.as_deref(), &req.decode)?;
        (d.image, d.source_format)
    } else if let Some(path) = &req.input_path {
        let d = decode_file(path, &req.decode)?;
        (d.image, d.source_format)
    } else {
        return Err(PicProError::InvalidArgument(
            "必须提供 input_bytes 或 input_path".into(),
        ));
    };

    if source_format.is_vector() {
        notes.push(format!("已将 SVG 栅格化为 {}x{} 位图", img.width, img.height));
    }
    let source_frames = img.frame_count();

    // ---------- 步骤 2：裁剪 ----------
    apply_crop(&mut img, &req.crop, &mut notes)?;

    // ---------- 步骤 3：换背景 ----------
    let mut bg_report = None;
    if let Some(bg_opts) = &req.background {
        // 动画 GIF 换背景本身不被产品需求覆盖，但内核支持逐帧处理；
        // 这里对多帧输入给出提示，避免用户误以为只处理了首帧。
        if img.frame_count() > 1 {
            notes.push(format!(
                "对 {} 帧逐帧换背景（用首帧估计背景色）",
                img.frame_count()
            ));
        }
        let out = replace_background(&img, bg_opts)?;
        // 背景占比过高的典型原因是：原图背景占比本就大（正常），
        // 或阈值过松把主体也判成了背景。超过 97% 时提示用户核对。
        if out.report.background_ratio > 0.97 {
            warnings.push(format!(
                "检出背景占比高达 {:.1}%，可能连主体一起被判为背景，建议调低背景阈值",
                out.report.background_ratio * 100.0
            ));
        }
        notes.push(format!(
            "检出背景色 RGB({:.0}, {:.0}, {:.0})，背景占比 {:.1}%",
            out.report.model.color[0],
            out.report.model.color[1],
            out.report.model.color[2],
            out.report.background_ratio * 100.0
        ));
        bg_report = Some(out.report);
        img = out.image;
    }

    // ---------- 步骤 4：确定输出格式 ----------
    let out_format = resolve_output_format(source_format, req.output_format)?;

    // 动画帧丢失提示：输出格式不支持动画时只能取首帧
    if source_frames > 1 && !out_format.supports_animation() {
        warnings.push(format!(
            "源文件有 {source_frames} 帧动画，但 {} 不支持动画，已只输出首帧",
            out_format.display_name()
        ));
    }
    // 透明通道丢失提示
    if !out_format.supports_alpha() && img.has_transparency() {
        notes.push(format!(
            "{} 不支持透明通道，已按设定底色压平",
            out_format.display_name()
        ));
    }

    // ---------- 步骤 5：压缩 + 编码 ----------
    let mut encode_opts = req.compress.encode.clone();
    encode_opts.format = out_format;

    let (bytes, width, height, quality, scale) = if req.compress.target_bytes.is_some()
        || req.compress.target_width.is_some()
        || req.compress.max_long_side.is_some()
    {
        let r = compress(
            &img,
            &CompressOptions {
                encode: encode_opts,
                ..req.compress.clone()
            },
        )?;
        // 质量未达下限说明是「保分辨率」优先的降级结果，需要提示
        if r.quality < req.compress.quality_floor && out_format.supports_quality() {
            warnings.push(format!(
                "体积上限较紧，质量为 {} 未达设定的下限 {}，如需更高质量请放宽体积或降低分辨率要求",
                r.quality, req.compress.quality_floor
            ));
        }
        (r.bytes, r.image.width, r.image.height, r.quality, r.scale)
    } else {
        let b = encode(&img, &encode_opts)?;
        (b, img.width, img.height, encode_opts.quality, 1.0)
    };

    Ok(PipelineOutput {
        bytes,
        width,
        height,
        format: out_format,
        source_format,
        quality,
        scale,
        background: bg_report,
        notes,
        warnings,
    })
}

/// 落实裁剪步骤。
///
/// 三种输入方式，优先级从高到低：
/// 1. `preset_id`：按证件照规格决定输出像素；裁剪框取用户指定值，
///    未指定则按规格比例自动构图；
/// 2. `rect` + `out_width/out_height`：自定义裁剪并缩放到精确像素；
/// 3. `rect`：仅裁剪，不改变像素（除裁剪本身）。
fn apply_crop(img: &mut RasterImage, spec: &CropSpec, notes: &mut Vec<String>) -> Result<()> {
    if spec.is_empty() {
        return Ok(());
    }

    // 解析出「裁剪框」与「目标像素」
    let (rect, out_w, out_h, label) = if let Some(id) = &spec.preset_id {
        let preset = find_preset(id)
            .ok_or_else(|| PicProError::InvalidArgument(format!("未知证件照规格 id：{id}")))?;
        let anchor = if spec.vertical_anchor > 0.0 {
            spec.vertical_anchor
        } else {
            0.06
        };
        // 用户有指定裁剪框就尊重用户，否则按比例自动构图
        let rect = spec.rect.unwrap_or_else(|| {
            suggest_crop_rect(
                img,
                preset.width_px as f32,
                preset.height_px as f32,
                anchor,
            )
        });
        (
            rect,
            Some(preset.width_px),
            Some(preset.height_px),
            format!("按「{}」规格裁剪", preset.name),
        )
    } else {
        let rect = match spec.rect {
            Some(r) => r,
            // 没有裁剪框也没规格：仅做了尺寸缩放，交给压缩步骤处理
            None => return Ok(()),
        };
        (rect, spec.out_width, spec.out_height, "裁剪".to_string())
    };

    *img = match (out_w, out_h) {
        // 有目标像素：裁剪后缩放到精确尺寸，保证输出严格合规
        (Some(w), Some(h)) => crop_to_exact_size(img, &rect, w, h)?,
        _ => crop(img, &rect)?,
    };
    notes.push(format!("{label} → {}x{}", img.width, img.height));
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::encode::EncodeOptions;
    use image::{Rgba, RgbaImage};

    /// 生成白底 + 中央深色矩形的测试图（便于验证换背景）
    fn sample_png(w: u32, h: u32) -> Vec<u8> {
        let mut im = RgbaImage::from_pixel(w, h, Rgba([255, 255, 255, 255]));
        for y in h / 4..h * 3 / 4 {
            for x in w / 4..w * 3 / 4 {
                im.put_pixel(x, y, Rgba([25, 25, 25, 255]));
            }
        }
        encode(
            &RasterImage::from_image(im),
            &EncodeOptions::for_format(ImageFormat::Png),
        )
        .unwrap()
    }

    fn base_req(bytes: Vec<u8>) -> PipelineRequest {
        PipelineRequest {
            input_bytes: Some(bytes),
            filename: Some("t.png".into()),
            ..Default::default()
        }
    }

    #[test]
    fn 仅压缩不改变格式() {
        let req = PipelineRequest {
            compress: CompressOptions {
                target_bytes: Some(20_000),
                ..Default::default()
            },
            ..base_req(sample_png(300, 200))
        };
        let out = run(&req).unwrap();
        // PNG 源且未指定格式，应仍输出 PNG
        assert_eq!(out.format, ImageFormat::Png);
        assert_eq!(out.source_format, ImageFormat::Png);
        assert!(out.bytes.len() <= 20_000);
    }

    #[test]
    fn 换背景后输出蓝底且给出报告() {
        let req = PipelineRequest {
            background: Some(BackgroundOptions {
                target_color: [67, 142, 219],
                ..Default::default()
            }),
            ..base_req(sample_png(120, 120))
        };
        let out = run(&req).unwrap();
        assert!(out.background.is_some());
        // 报告里应给出检出的背景色（白）
        let r = out.background.unwrap();
        assert!(r.model.color[0] > 240.0, "应检出白色背景");

        // 解码输出验证四角变蓝
        let dec = decode_bytes(&out.bytes, None, &DecodeOptions::default()).unwrap();
        let px = dec.image.first().get_pixel(2, 2).0;
        assert_eq!([px[0], px[1], px[2]], [67, 142, 219]);
    }

    #[test]
    fn 按一寸规格裁剪得到精确像素() {
        let req = PipelineRequest {
            crop: CropSpec {
                preset_id: Some("size_1cun".into()),
                ..Default::default()
            },
            ..base_req(sample_png(600, 800))
        };
        let out = run(&req).unwrap();
        assert_eq!((out.width, out.height), (295, 413), "应符合一寸规格像素");
        // 应记录了裁剪说明
        assert!(out.notes.iter().any(|n| n.contains("一寸")));
    }

    #[test]
    fn 裁剪与换背景与压缩可叠加且顺序正确() {
        let req = PipelineRequest {
            crop: CropSpec {
                preset_id: Some("size_1cun".into()),
                ..Default::default()
            },
            background: Some(BackgroundOptions {
                target_color: [255, 255, 255],
                ..Default::default()
            }),
            compress: CompressOptions {
                // 证件照常见的小体积要求
                target_bytes: Some(40_000),
                ..Default::default()
            },
            ..base_req(sample_png(800, 1000))
        };
        let out = run(&req).unwrap();
        // 关键约束：先裁剪到规定像素，因此输出像素必须严格等于规格值，
        // 压缩只能通过降低 JPEG 质量实现，而不得改变像素尺寸
        assert_eq!(
            (out.width, out.height),
            (295, 413),
            "压缩不应改变裁剪后的规定像素"
        );
        assert!(out.bytes.len() <= 40_000);
    }

    #[test]
    fn 源为svg时默认输出png() {
        let svg = br##"<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40"><rect width="40" height="40" fill="#00FF00"/></svg>"##;
        let req = base_req(svg.to_vec());
        let out = run(&req).unwrap();
        assert_eq!(out.source_format, ImageFormat::Svg);
        assert_eq!(out.format, ImageFormat::Png, "SVG 源应默认转 PNG");
        assert!(out.notes.iter().any(|n| n.contains("栅格化")));
    }

    #[test]
    fn 显式要求svg输出被拒绝() {
        let req = PipelineRequest {
            output_format: Some(ImageFormat::Svg),
            ..base_req(sample_png(20, 20))
        };
        assert!(matches!(
            run(&req),
            Err(PicProError::UnsupportedFormat(_))
        ));
    }

    #[test]
    fn 动画转静态格式时给出警告() {
        // 造一个两帧 GIF
        let mut frames = Vec::new();
        for i in 0..2u8 {
            frames.push(crate::core::types::Frame {
                pixels: RgbaImage::from_pixel(20, 20, Rgba([i * 100, 0, 0, 255])),
                delay_ms: 100,
            });
        }
        let gif = encode(
            &RasterImage::from_frames(20, 20, frames),
            &EncodeOptions::for_format(ImageFormat::Gif),
        )
        .unwrap();

        let req = PipelineRequest {
            output_format: Some(ImageFormat::Jpeg),
            ..base_req(gif)
        };
        let out = run(&req).unwrap();
        assert_eq!(out.format, ImageFormat::Jpeg);
        assert!(
            out.warnings.iter().any(|w| w.contains("首帧")),
            "应提示动画帧被丢弃，实际警告：{:?}",
            out.warnings
        );
    }

    #[test]
    fn 缺少输入时报错() {
        let req = PipelineRequest::default();
        assert!(matches!(
            run(&req),
            Err(PicProError::InvalidArgument(_))
        ));
    }

    #[test]
    fn 未知规格id报错() {
        let req = PipelineRequest {
            crop: CropSpec {
                preset_id: Some("no_such_preset".into()),
                ..Default::default()
            },
            ..base_req(sample_png(50, 50))
        };
        assert!(matches!(
            run(&req),
            Err(PicProError::InvalidArgument(_))
        ));
    }

    #[test]
    fn 输出格式推断规则() {
        // 用户指定优先
        assert_eq!(
            resolve_output_format(ImageFormat::Png, Some(ImageFormat::Jpeg)).unwrap(),
            ImageFormat::Jpeg
        );
        // SVG 源默认 PNG
        assert_eq!(
            resolve_output_format(ImageFormat::Svg, None).unwrap(),
            ImageFormat::Png
        );
        // 其余沿用源格式
        assert_eq!(
            resolve_output_format(ImageFormat::WebP, None).unwrap(),
            ImageFormat::WebP
        );
    }

    #[test]
    fn 从文件路径读取也能跑通() {
        // 写入临时文件验证 path 分支
        let dir = std::env::temp_dir();
        let path = dir.join("picpro_pipeline_test.png");
        std::fs::write(&path, sample_png(60, 60)).unwrap();
        let req = PipelineRequest {
            input_path: Some(path.to_string_lossy().to_string()),
            ..Default::default()
        };
        let out = run(&req).unwrap();
        assert_eq!((out.width, out.height), (60, 60));
        let _ = std::fs::remove_file(&path);
    }
}
