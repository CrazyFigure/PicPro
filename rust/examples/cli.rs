//! PicPro 内核命令行示例。
//!
//! 既可用来验证内核行为，也可直接当作命令行工具使用：
//!
//! ```bash
//! # 查看图片信息
//! cargo run --release --example cli -- input.jpg --info
//!
//! # 换蓝底并压到 200KB 以内
//! cargo run --release --example cli -- input.jpg out.jpg --bg 67,142,219 --max-kb 200
//!
//! # 按一寸规格裁剪 + 换白底 + 压到 100KB
//! cargo run --release --example cli -- in.jpg out.jpg --preset size_1cun --bg 255,255,255 --max-kb 100
//!
//! # 转成 PNG
//! cargo run --release --example cli -- in.webp out.png --format png
//! ```
//!
//! 选项可任意组合，执行顺序固定为：裁剪 → 换背景 → 压缩 → 编码。

use picpro_core::core::background::{replace_background, BackgroundOptions};
use picpro_core::core::compress::{compress, CompressOptions, format_bytes};
use picpro_core::core::crop::{crop_to_exact_size, CropRect};
use picpro_core::core::decode::{decode_file, DecodeOptions};
use picpro_core::core::encode::{encode_to_file, EncodeOptions};
use picpro_core::core::format::ImageFormat;
use picpro_core::core::presets::{find_preset, PresetBackground};

/// 命令行参数集合。
struct Args {
    input: String,
    output: Option<String>,
    max_kb: Option<u64>,
    bg: Option<[u8; 3]>,
    preset: Option<String>,
    format: Option<ImageFormat>,
    quality: Option<u8>,
    tolerance: Option<f32>,
    crop: Option<CropRect>,
    no_decontaminate: bool,
    info_only: bool,
}

/// 解析形如 `R,G,B` 的颜色。
fn parse_color(s: &str) -> Result<[u8; 3], String> {
    let parts: Vec<&str> = s.split(',').collect();
    if parts.len() != 3 {
        return Err(format!("颜色需为 R,G,B 三段，收到：{s}"));
    }
    let mut out = [0u8; 3];
    for (i, p) in parts.iter().enumerate() {
        out[i] = p
            .trim()
            .parse::<u8>()
            .map_err(|_| format!("颜色分量无法解析为 0~255：{p}"))?;
    }
    Ok(out)
}

/// 解析形如 `x,y,w,h` 的归一化裁剪框。
fn parse_crop(s: &str) -> Result<CropRect, String> {
    let parts: Vec<&str> = s.split(',').collect();
    if parts.len() != 4 {
        return Err(format!("裁剪框需为 x,y,w,h 四段，收到：{s}"));
    }
    let mut v = [0f32; 4];
    for (i, p) in parts.iter().enumerate() {
        v[i] = p
            .trim()
            .parse::<f32>()
            .map_err(|_| format!("裁剪框分量无法解析为数值：{p}"))?;
    }
    Ok(CropRect::new(v[0], v[1], v[2], v[3]))
}

fn parse_args() -> Result<Args, String> {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    if argv.is_empty() {
        return Err(usage());
    }
    let mut args = Args {
        input: String::new(),
        output: None,
        max_kb: None,
        bg: None,
        preset: None,
        format: None,
        quality: None,
        tolerance: None,
        crop: None,
        no_decontaminate: false,
        info_only: false,
    };

    let mut i = 0;
    while i < argv.len() {
        let a = argv[i].as_str();
        match a {
            "--info" => args.info_only = true,
            "--no-decontaminate" => args.no_decontaminate = true,
            "--max-kb" => {
                i += 1;
                args.max_kb = Some(
                    argv.get(i)
                        .ok_or("--max-kb 缺少取值")?
                        .parse()
                        .map_err(|_| "--max-kb 需为整数".to_string())?,
                );
            }
            "--bg" => {
                i += 1;
                args.bg = Some(parse_color(argv.get(i).ok_or("--bg 缺少取值")?)?);
            }
            "--preset" => {
                i += 1;
                args.preset = Some(argv.get(i).ok_or("--preset 缺少取值")?.clone());
            }
            "--format" => {
                i += 1;
                let v = argv.get(i).ok_or("--format 缺少取值")?;
                args.format = Some(
                    ImageFormat::from_extension(v)
                        .ok_or_else(|| format!("不支持的格式：{v}"))?,
                );
            }
            "--quality" => {
                i += 1;
                let q: u8 = argv
                    .get(i)
                    .ok_or("--quality 缺少取值")?
                    .parse()
                    .map_err(|_| "--quality 需为 1~100 整数".to_string())?;
                if q == 0 || q > 100 {
                    return Err("--quality 取值范围为 1~100".into());
                }
                args.quality = Some(q);
            }
            "--tolerance" => {
                i += 1;
                args.tolerance = Some(
                    argv.get(i)
                        .ok_or("--tolerance 缺少取值")?
                        .parse()
                        .map_err(|_| "--tolerance 需为 0~1 数值".to_string())?,
                );
            }
            "--crop" => {
                i += 1;
                args.crop = Some(parse_crop(argv.get(i).ok_or("--crop 缺少取值")?)?);
            }
            _ if a.starts_with("--") => return Err(format!("未知选项：{a}")),
            _ => {
                // 位置参数：第一个是输入，第二个是输出
                if args.input.is_empty() {
                    args.input = a.to_string();
                } else if args.output.is_none() {
                    args.output = Some(a.to_string());
                } else {
                    return Err(format!("多余的位置参数：{a}"));
                }
            }
        }
        i += 1;
    }

    if args.input.is_empty() {
        return Err(usage());
    }
    Ok(args)
}

fn usage() -> String {
    "用法: cli <输入> [输出] [选项]\n\
     \n\
     选项:\n\
       --info                    只打印图片信息，不做处理\n\
       --max-kb <N>              输出体积上限（KB）\n\
       --bg <R,G,B>              替换背景为指定颜色，如 67,142,219\n\
       --preset <id>             按证件照规格裁剪，如 size_1cun\n\
       --crop <x,y,w,h>          自定义归一化裁剪框\n\
       --format <fmt>            png|jpg|gif|webp|bmp|tiff\n\
       --quality <1-100>         JPEG 质量\n\
       --tolerance <0-1>         背景判定阈值，默认 0.12\n\
       --no-decontaminate        关闭白底去污染\n\
     \n\
     常用规格: size_1cun(一寸) size_2cun(二寸) doc_idcard(身份证)\n\
               exam_kaoyan(考研) exam_chsi(学信网) visa_us(美国签证)"
        .to_string()
}

fn main() {
    if let Err(e) = run() {
        eprintln!("错误：{e}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let args = parse_args()?;

    // ---------- 解码 ----------
    let decoded = decode_file(&args.input, &DecodeOptions::default())
        .map_err(|e| e.to_string())?;
    let mut img = decoded.image;
    println!(
        "输入: {} | {}x{} | {} | {} 帧",
        args.input,
        img.width,
        img.height,
        decoded.source_format.display_name(),
        img.frame_count()
    );

    if args.info_only {
        return Ok(());
    }

    // 输出路径与格式
    let output = args
        .output
        .clone()
        .ok_or("需要指定输出路径（或使用 --info 仅查看信息）")?;
    let out_format = match args.format {
        Some(f) => f,
        None => {
            // 未指定则按输出扩展名推断，再退化为 JPEG
            std::path::Path::new(&output)
                .extension()
                .and_then(|e| e.to_str())
                .and_then(ImageFormat::from_extension)
                .unwrap_or(ImageFormat::Jpeg)
        }
    };

    // ---------- 步骤 1：裁剪 ----------
    if let Some(preset_id) = &args.preset {
        let preset = find_preset(preset_id)
            .ok_or_else(|| format!("未知规格 id：{preset_id}"))?;
        // 未显式给出裁剪框时，按目标比例自动生成居中构图
        let rect = args.crop.unwrap_or_else(|| {
            picpro_core::core::crop::suggest_crop_rect(
                &img,
                preset.width_px as f32,
                preset.height_px as f32,
                0.06,
            )
        });
        img = crop_to_exact_size(&img, &rect, preset.width_px, preset.height_px)
            .map_err(|e| e.to_string())?;
        println!(
            "裁剪: {} → {}x{} ({})",
            preset.name,
            img.width,
            img.height,
            preset.note
        );
    } else if let Some(rect) = &args.crop {
        img = picpro_core::core::crop::crop(&img, rect).map_err(|e| e.to_string())?;
        println!("裁剪: 自定义框 → {}x{}", img.width, img.height);
    }

    // ---------- 步骤 2：换背景 ----------
    if let Some(color) = args.bg {
        let out = replace_background(
            &img,
            &BackgroundOptions {
                target_color: color,
                tolerance: args.tolerance.unwrap_or(0.12),
                decontaminate: !args.no_decontaminate,
                ..Default::default()
            },
        )
        .map_err(|e| e.to_string())?;
        img = out.image;
        println!(
            "换背景: 目标色 {:?} | 检出背景色 [{:.0}, {:.0}, {:.0}] | 背景占比 {:.1}% | 半透明 {:.1}%",
            color,
            out.report.model.color[0],
            out.report.model.color[1],
            out.report.model.color[2],
            out.report.background_ratio * 100.0,
            out.report.feathered_ratio * 100.0
        );
    }

    // ---------- 步骤 3：压缩 + 编码 ----------
    let encode_opts = EncodeOptions {
        format: out_format,
        quality: args.quality.unwrap_or(90),
        ..Default::default()
    };

    if let Some(kb) = args.max_kb {
        let r = compress(
            &img,
            &CompressOptions {
                target_bytes: Some(kb * 1024),
                encode: encode_opts,
                ..Default::default()
            },
        )
        .map_err(|e| e.to_string())?;
        std::fs::write(&output, &r.bytes).map_err(|e| e.to_string())?;
        println!(
            "输出: {} | {}x{} | {} | 质量 {} | 缩放 {:.2}x | 尝试 {} 次",
            output,
            r.image.width,
            r.image.height,
            format_bytes(r.bytes.len() as u64),
            r.quality,
            r.scale,
            r.attempts
        );
    } else {
        let n = encode_to_file(&img, &output, &encode_opts).map_err(|e| e.to_string())?;
        println!(
            "输出: {} | {}x{} | {}",
            output,
            img.width,
            img.height,
            format_bytes(n as u64)
        );
    }

    // 提示规格的推荐底色，便于用户核对
    if let Some(preset_id) = &args.preset {
        if let Some(p) = find_preset(preset_id) {
            let names: Vec<&str> = p
                .backgrounds
                .iter()
                .map(|b| b.display_name())
                .collect();
            println!("该规格常用底色: {}", names.join(" / "));
            if args.bg.is_none() {
                // 未指定底色时，给出该规格最常见底色作为建议
                let suggested = p.backgrounds[0];
                if suggested != PresetBackground::Blue {
                    println!("提示: 可用 --bg {} 换成{}", rgb_to_arg(suggested), suggested.display_name());
                }
            }
        }
    }
    Ok(())
}

/// 把底色枚举转成 `R,G,B` 命令行字面量。
fn rgb_to_arg(b: PresetBackground) -> String {
    let c = b.rgb();
    format!("{},{},{}", c[0], c[1], c[2])
}
