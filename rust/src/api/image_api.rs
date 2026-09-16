//! 对外暴露的处理接口。
//!
//! Dart 侧调用的每个函数都在这里。函数默认在 FRB 的工作线程池上执行，
//! 不会阻塞 UI 线程；`process_batch` 额外通过 `StreamSink` 回报进度。
//!
//! **错误类型**：统一使用内核的 [`PicProError`]，而不是 `anyhow::Error`。
//! 这一点很关键——FRB 会把 `Result<T, E>` 的 `E` 导出为 Dart 异常类，
//! 从而让界面能够区分「可提示用户调整参数」的错误（如体积无法达标）
//! 与真正的失败（如文件损坏），而不是只拿到一句字符串。

use crate::api::dto::*;
use crate::core::background::BackgroundOptions;
use crate::core::compress::CompressOptions;
use crate::core::crop::CropRect;
use crate::core::decode::{decode_bytes, DecodeOptions};
use crate::core::encode::EncodeOptions;
use crate::core::error::{PicProError, Result};
use crate::core::format::ImageFormat;
use crate::core::pipeline::{run, CropSpec, PipelineOutput, PipelineRequest};
use crate::core::presets::{all_presets, PresetBackground};
use crate::frb_generated::StreamSink;

/// 内核版本号。
pub fn core_version() -> String {
    crate::CORE_VERSION.to_string()
}

/// 列出全部证件照规格预设。
pub fn list_presets() -> Vec<PresetDto> {
    all_presets()
        .iter()
        .map(|p| PresetDto {
            id: p.id.to_string(),
            name: p.name.to_string(),
            category: format!("{:?}", p.category),
            category_name: p.category.display_name().to_string(),
            width_mm: p.width_mm,
            height_mm: p.height_mm,
            width_px: p.width_px,
            height_px: p.height_px,
            dpi: p.dpi,
            background_names: p
                .backgrounds
                .iter()
                .map(|b| b.display_name().to_string())
                .collect(),
            background_colors: p
                .backgrounds
                .iter()
                .map(|b| {
                    let c = b.rgb();
                    ColorDto {
                        red: c[0] as u32,
                        green: c[1] as u32,
                        blue: c[2] as u32,
                    }
                })
                .collect(),
            note: p.note.to_string(),
        })
        .collect()
}

/// 常用底色的标准色值，供界面直接使用，避免前端重复硬编码色号。
pub fn standard_backgrounds() -> Vec<BackgroundChoiceDto> {
    [
        PresetBackground::Blue,
        PresetBackground::DarkBlue,
        PresetBackground::LightBlue,
        PresetBackground::White,
        PresetBackground::Red,
        PresetBackground::Grey,
    ]
    .iter()
    .map(|b| {
        let c = b.rgb();
        BackgroundChoiceDto {
            name: b.display_name().to_string(),
            color: ColorDto {
                red: c[0] as u32,
                green: c[1] as u32,
                blue: c[2] as u32,
            },
        }
    })
    .collect()
}

/// 探测图片基础信息。
///
/// 只读取必要信息（尺寸、格式、GIF 帧数），不做完整像素解码，
/// 因此对超大图也能快速返回，适合在文件导入后立即展示。
pub fn probe_image(bytes: Vec<u8>, filename: Option<String>) -> Result<ImageInfoDto> {
    let format = ImageFormat::detect(&bytes, filename.as_deref())?;
    let byte_size = bytes.len() as u64;

    if format == ImageFormat::Svg {
        // SVG 需要解析才能得到尺寸
        let tree = resvg::usvg::Tree::from_data(&bytes, &resvg::usvg::Options::default())
            .map_err(|e| PicProError::Svg(format!("SVG 解析失败：{e}")))?;
        let size = tree.size();
        return Ok(ImageInfoDto {
            width: size.width().round().max(1.0) as u32,
            height: size.height().round().max(1.0) as u32,
            format: format.extension().to_string(),
            format_name: format.display_name().to_string(),
            frame_count: 1,
            byte_size,
            source_supports_alpha: true,
            source_supports_animation: false,
        });
    }

    // 位图只读头部尺寸，避免为「看一眼信息」付出整图解码代价
    let reader = image::ImageReader::new(std::io::Cursor::new(&bytes))
        .with_guessed_format()
        .map_err(|e| PicProError::Decode(format!("读取图片头失败：{e}")))?;
    let (w, h) = reader
        .into_dimensions()
        .map_err(|e| PicProError::Decode(format!("读取图片尺寸失败：{e}")))?;

    // GIF 需要实际遍历帧才能得到帧数；GIF 通常体积小，代价可接受
    let frame_count = if format == ImageFormat::Gif {
        decode_bytes(
            &bytes,
            filename.as_deref(),
            &DecodeOptions {
                decode_all_frames: true,
                ..Default::default()
            },
        )
        .map(|d| d.image.frame_count() as u32)
        .unwrap_or(1)
    } else {
        1
    };

    Ok(ImageInfoDto {
        width: w,
        height: h,
        format: format.extension().to_string(),
        format_name: format.display_name().to_string(),
        frame_count,
        byte_size,
        source_supports_alpha: format.supports_alpha(),
        source_supports_animation: format.supports_animation(),
    })
}

/// 处理单张图片（字节输入，三端通用）。
pub fn process_image(
    bytes: Vec<u8>,
    filename: Option<String>,
    options: ProcessOptionsDto,
) -> Result<ProcessResultDto> {
    let resolved = resolve_options(&options)?;
    let req = PipelineRequest {
        input_bytes: Some(bytes),
        input_path: None,
        filename,
        crop: resolved.crop,
        background: resolved.background,
        compress: resolved.compress,
        output_format: resolved.output_format,
        decode: resolved.decode,
    };
    let out = run(&req)?;
    Ok(to_result_dto(out))
}

/// 处理单张图片（路径输入，仅原生端可用，可省去 Dart 侧读取与拷贝）。
pub fn process_image_file(path: String, options: ProcessOptionsDto) -> Result<ProcessResultDto> {
    let resolved = resolve_options(&options)?;
    let req = PipelineRequest {
        input_bytes: None,
        input_path: Some(path),
        filename: None,
        crop: resolved.crop,
        background: resolved.background,
        compress: resolved.compress,
        output_format: resolved.output_format,
        decode: resolved.decode,
    };
    let out = run(&req)?;
    Ok(to_result_dto(out))
}

/// 生成预览图。
///
/// 预览走的是**与正式处理完全相同的流水线**，只是把输出限制在较小的
/// 长边并强制 JPEG 编码。这样预览所见即所得——包括换背景后的真实边缘效果，
/// 而不是另做一套近似渲染导致预览与成品不一致。
///
/// `max_side` 建议取 600~1200：过小看不清换背景边缘，过大则失去快速预览的意义。
pub fn make_preview(
    bytes: Vec<u8>,
    filename: Option<String>,
    options: ProcessOptionsDto,
    max_side: u32,
) -> Result<Vec<u8>> {
    let mut resolved = resolve_options(&options)?;
    // 预览固定输出 JPEG：体积小、解码快，且换背景后已无透明区
    resolved.compress = CompressOptions {
        // 保留裁剪与背景参数，仅替换尺寸与编码设定
        target_bytes: None,
        max_long_side: Some(max_side.max(64)),
        target_width: None,
        target_height: None,
        allow_upscale: false,
        ..resolved.compress
    };
    resolved.output_format = Some(ImageFormat::Jpeg);

    let req = PipelineRequest {
        input_bytes: Some(bytes),
        input_path: None,
        filename,
        crop: resolved.crop,
        background: resolved.background,
        compress: resolved.compress,
        output_format: resolved.output_format,
        decode: resolved.decode,
    };
    let out = run(&req)?;
    Ok(out.bytes)
}

/// 批量处理，逐个回报进度。
///
/// 原生端使用 rayon 并行处理（进度通过通道汇总到单线程再推给 Dart，
/// 避免多线程同时写 sink 造成顺序错乱）；WASM 端无 rayon，退化为串行。
/// 每一项独立成败：单项失败不会中断整批，失败信息随该项的进度一起回报。
pub fn process_batch(
    items: Vec<BatchItemDto>,
    options: ProcessOptionsDto,
    sink: StreamSink<BatchProgressDto>,
) {
    // 参数解析失败属于整批级别的错误，直接以一条全失败进度回报，
    // 避免 Dart 侧需要区分「批级异常」与「单项异常」两种处理路径。
    let resolved = match resolve_options(&options) {
        Ok(r) => r,
        Err(e) => {
            let msg = format!("{e}");
            for (i, item) in items.iter().enumerate() {
                let _ = sink.add(BatchProgressDto {
                    index: i as u32,
                    id: item.id.clone(),
                    done: i as u32 + 1,
                    total: items.len() as u32,
                    succeeded: 0,
                    failed: i as u32 + 1,
                    result: None,
                    error: Some(msg.clone()),
                });
            }
            return;
        }
    };

    let total = items.len() as u32;
    let succeeded = std::sync::atomic::AtomicU32::new(0);
    let failed = std::sync::atomic::AtomicU32::new(0);
    let done = std::sync::atomic::AtomicU32::new(0);

    // 处理单项并组装进度回报
    let handle = |item: &BatchItemDto, index: u32| -> BatchProgressDto {
        let req = PipelineRequest {
            input_bytes: Some(item.bytes.clone()),
            input_path: None,
            filename: item.filename.clone(),
            crop: resolved.crop.clone(),
            background: resolved.background.clone(),
            compress: resolved.compress.clone(),
            output_format: resolved.output_format,
            decode: resolved.decode.clone(),
        };
        let (result, error) = match run(&req) {
            Ok(out) => {
                succeeded.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                (Some(to_result_dto(out)), None)
            }
            Err(e) => {
                failed.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                (None, Some(format!("{e}")))
            }
        };
        let d = done.fetch_add(1, std::sync::atomic::Ordering::Relaxed) + 1;
        BatchProgressDto {
            index,
            id: item.id.clone(),
            done: d,
            total,
            succeeded: succeeded.load(std::sync::atomic::Ordering::Relaxed),
            failed: failed.load(std::sync::atomic::Ordering::Relaxed),
            result,
            error,
        }
    };

    #[cfg(not(target_arch = "wasm32"))]
    {
        use rayon::prelude::*;
        let (tx, rx) = std::sync::mpsc::channel::<BatchProgressDto>();
        std::thread::scope(|scope| {
            // 汇总线程：唯一向 sink 写入的地方，保证 Dart 侧收到有序事件
            scope.spawn(move || {
                for p in rx {
                    // 写入失败说明 Dart 侧已取消监听，直接停止即可
                    if sink.add(p).is_err() {
                        break;
                    }
                }
            });
            items.par_iter().enumerate().for_each(|(i, item)| {
                let p = handle(item, i as u32);
                // 接收端已关闭时忽略发送错误
                let _ = tx.send(p);
            });
            // 释放发送端，让汇总线程的 for 循环自然结束
            drop(tx);
        });
    }

    #[cfg(target_arch = "wasm32")]
    {
        // WASM 无多线程，串行处理
        for (i, item) in items.iter().enumerate() {
            let p = handle(item, i as u32);
            if sink.add(p).is_err() {
                break;
            }
        }
    }
}

/// 已解析的内核参数，跨线程共享时需要可克隆。
#[derive(Clone)]
struct ResolvedOptions {
    crop: CropSpec,
    background: Option<BackgroundOptions>,
    compress: CompressOptions,
    output_format: Option<ImageFormat>,
    decode: DecodeOptions,
}

/// 把 DTO 映射为内核参数。
///
/// 未提供的项一律回落到内核默认值，Dart 侧只需传「用户改过的」字段。
fn resolve_options(dto: &ProcessOptionsDto) -> Result<ResolvedOptions> {
    // ---------- 输出格式 ----------
    let output_format = match &dto.output_format {
        Some(s) if !s.trim().is_empty() => Some(
            ImageFormat::from_extension(s)
                .ok_or_else(|| PicProError::UnsupportedFormat(format!("不支持的输出格式：{s}")))?,
        ),
        _ => None,
    };

    // ---------- 裁剪 ----------
    let crop = match &dto.crop {
        Some(c) => CropSpec {
            rect: c.rect.map(|r| CropRect::new(r.x, r.y, r.width, r.height)),
            out_width: c.out_width,
            out_height: c.out_height,
            preset_id: c.preset_id.clone(),
            vertical_anchor: c.vertical_anchor.unwrap_or(0.06),
        },
        None => CropSpec::default(),
    };

    // ---------- 换背景 ----------
    let background = match &dto.background {
        Some(b) => Some(BackgroundOptions {
            target_color: b.color.to_rgb(),
            tolerance: b.tolerance.unwrap_or(0.12),
            feather_px: b.feather_px.unwrap_or(2),
            decontaminate: b.decontaminate.unwrap_or(true),
            edge_offset: b.edge_offset.unwrap_or(0.0),
            smooth_alpha: b.smooth_alpha.unwrap_or(true),
            preserve_original_alpha: true,
        }),
        None => None,
    };

    // ---------- 压缩与编码 ----------
    let defaults = CompressOptions::default();
    let mut encode = EncodeOptions::default();
    if let Some(f) = output_format {
        encode.format = f;
    }
    if let Some(c) = &dto.flatten_color {
        encode.flatten_background = c.to_rgb();
    }

    let compress = match &dto.compress {
        Some(c) => {
            if let Some(q) = c.quality_max {
                encode.quality = q.clamp(1, 100) as u8;
            }
            if let Some(b) = c.jpeg_no_chroma_subsampling {
                encode.jpeg_no_chroma_subsampling = b;
            }
            if let Some(b) = c.png_best_compression {
                encode.png_best_compression = b;
            }
            CompressOptions {
                target_bytes: c.target_bytes,
                max_long_side: c.max_long_side,
                quality_floor: c
                    .quality_floor
                    .map(|v| v.clamp(1, 100) as u8)
                    .unwrap_or(defaults.quality_floor),
                // 质量下限不得高于上限，否则搜索区间为空
                quality_max: c
                    .quality_max
                    .map(|v| v.clamp(1, 100) as u8)
                    .unwrap_or(defaults.quality_max),
                quality_min: defaults.quality_min.min(
                    c.quality_floor
                        .map(|v| v.clamp(1, 100) as u8)
                        .unwrap_or(defaults.quality_floor),
                ),
                min_long_side: c.min_long_side.unwrap_or(defaults.min_long_side),
                encode,
                ..defaults
            }
        }
        None => CompressOptions {
            encode,
            ..defaults
        },
    };

    // ---------- 解码 ----------
    let decode = DecodeOptions {
        svg_target_width: dto.svg_render_width,
        decode_all_frames: true,
        ..Default::default()
    };

    Ok(ResolvedOptions {
        crop,
        background,
        compress,
        output_format,
        decode,
    })
}

/// 内核输出 → DTO。
fn to_result_dto(out: PipelineOutput) -> ProcessResultDto {
    ProcessResultDto {
        bytes: out.bytes,
        width: out.width,
        height: out.height,
        format: out.format.extension().to_string(),
        format_name: out.format.display_name().to_string(),
        source_format_name: out.source_format.display_name().to_string(),
        quality: out.quality as u32,
        scale: out.scale,
        background_ratio: out.background.map(|b| b.background_ratio),
        feathered_ratio: out.background.map(|b| b.feathered_ratio),
        detected_background: out.background.map(|b| ColorDto {
            red: b.model.color[0].round().clamp(0.0, 255.0) as u32,
            green: b.model.color[1].round().clamp(0.0, 255.0) as u32,
            blue: b.model.color[2].round().clamp(0.0, 255.0) as u32,
        }),
        notes: out.notes,
        warnings: out.warnings,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{Rgba, RgbaImage};

    fn png_bytes(w: u32, h: u32) -> Vec<u8> {
        let mut im = RgbaImage::from_pixel(w, h, Rgba([255, 255, 255, 255]));
        for y in h / 4..h * 3 / 4 {
            for x in w / 4..w * 3 / 4 {
                im.put_pixel(x, y, Rgba([30, 30, 30, 255]));
            }
        }
        let mut out = Vec::new();
        image::DynamicImage::ImageRgba8(im)
            .write_to(&mut std::io::Cursor::new(&mut out), image::ImageFormat::Png)
            .unwrap();
        out
    }

    #[test]
    fn 规格列表非空且字段完整() {
        let list = list_presets();
        assert!(!list.is_empty());
        let one = list.iter().find(|p| p.id == "size_1cun").unwrap();
        assert_eq!(one.name, "一寸");
        assert_eq!(one.category_name, "基础寸照");
        assert_eq!((one.width_px, one.height_px), (295, 413));
        // 一寸应含蓝白红三种底色
        assert_eq!(one.background_colors.len(), 3);
        assert!(!one.note.is_empty());
    }

    #[test]
    fn 标准底色含蓝白红() {
        let list = standard_backgrounds();
        let blue = list.iter().find(|b| b.name == "蓝底").unwrap();
        assert_eq!(
            (blue.color.red, blue.color.green, blue.color.blue),
            (67, 142, 219)
        );
        assert!(list.iter().any(|b| b.name == "白底"));
        assert!(list.iter().any(|b| b.name == "红底"));
    }

    #[test]
    fn 探测图片信息() {
        let info = probe_image(png_bytes(120, 90), Some("a.png".into())).unwrap();
        assert_eq!((info.width, info.height), (120, 90));
        assert_eq!(info.format, "png");
        assert_eq!(info.frame_count, 1);
        assert!(info.byte_size > 0);
        assert!(info.source_supports_alpha);
        assert!(!info.source_supports_animation);
    }

    #[test]
    fn 探测svg尺寸() {
        let svg = br##"<svg xmlns="http://www.w3.org/2000/svg" width="64" height="48"/>"##;
        let info = probe_image(svg.to_vec(), None).unwrap();
        assert_eq!((info.width, info.height), (64, 48));
        assert_eq!(info.format, "svg");
    }

    #[test]
    fn 处理图片默认参数可直接跑通() {
        let out = process_image(png_bytes(100, 100), None, empty_options()).unwrap();
        assert_eq!((out.width, out.height), (100, 100));
        assert!(!out.bytes.is_empty());
        assert_eq!(out.format, "png");
    }

    #[test]
    fn 换背景返回检测结果() {
        let opts = ProcessOptionsDto {
            background: Some(BackgroundDto {
                color: ColorDto {
                    red: 67,
                    green: 142,
                    blue: 219,
                },
                tolerance: None,
                feather_px: None,
                decontaminate: None,
                edge_offset: None,
                smooth_alpha: None,
            }),
            ..empty_options()
        };
        let out = process_image(png_bytes(120, 120), None, opts).unwrap();
        let bg = out.detected_background.unwrap();
        // 原背景为纯白，应检出接近白色
        assert!(bg.red > 240 && bg.green > 240 && bg.blue > 240);
        assert!(out.background_ratio.unwrap() > 0.5);
    }

    #[test]
    fn 按规格裁剪得到规定像素() {
        let opts = ProcessOptionsDto {
            crop: Some(CropDto {
                preset_id: Some("size_2cun".into()),
                rect: None,
                out_width: None,
                out_height: None,
                vertical_anchor: None,
            }),
            ..empty_options()
        };
        let out = process_image(png_bytes(900, 1200), None, opts).unwrap();
        // 二寸规格 413x579
        assert_eq!((out.width, out.height), (413, 579));
    }

    #[test]
    fn 体积上限生效且像素不变() {
        // 先裁到规定像素，再压体积——像素不得被压缩步骤改变
        let opts = ProcessOptionsDto {
            output_format: Some("jpg".into()),
            crop: Some(CropDto {
                preset_id: Some("size_1cun".into()),
                rect: None,
                out_width: None,
                out_height: None,
                vertical_anchor: None,
            }),
            compress: Some(CompressDto {
                target_bytes: Some(30_000),
                max_long_side: None,
                quality_max: None,
                quality_floor: None,
                min_long_side: None,
                jpeg_no_chroma_subsampling: None,
                png_best_compression: None,
            }),
            ..empty_options()
        };
        let out = process_image(png_bytes(800, 1000), None, opts).unwrap();
        assert_eq!((out.width, out.height), (295, 413));
        assert!(out.bytes.len() <= 30_000);
    }

    #[test]
    fn 预览图尺寸受限且为jpeg() {
        let preview = make_preview(png_bytes(1600, 1200), None, empty_options(), 400).unwrap();
        let decoded = decode_bytes(&preview, None, &DecodeOptions::default()).unwrap();
        // 长边应被限制到 400
        assert_eq!(decoded.image.width.max(decoded.image.height), 400);
        assert_eq!(decoded.source_format, ImageFormat::Jpeg);
    }

    #[test]
    fn 未知输出格式报错() {
        let opts = ProcessOptionsDto {
            output_format: Some("heic".into()),
            ..empty_options()
        };
        assert!(process_image(png_bytes(20, 20), None, opts).is_err());
    }

    #[test]
    fn 处理不可识别的数据报错而非panic() {
        let r = process_image(b"not an image".to_vec(), Some("x.txt".into()), empty_options());
        assert!(r.is_err());
    }

    /// 构造一份「全部走默认值」的参数
    fn empty_options() -> ProcessOptionsDto {
        ProcessOptionsDto {
            output_format: None,
            crop: None,
            background: None,
            compress: None,
            flatten_color: None,
            svg_render_width: None,
        }
    }
}
