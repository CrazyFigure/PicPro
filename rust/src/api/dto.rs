//! FFI 数据传输对象（DTO）。
//!
//! 这些类型会由 flutter_rust_bridge 生成对应的 Dart 类，
//! 因此字段命名与含义需要保持稳定，避免影响已生成的 Dart 接口。

/// RGB 颜色。
#[derive(Debug, Clone, Copy)]
pub struct ColorDto {
    pub red: u32,
    pub green: u32,
    pub blue: u32,
}

impl ColorDto {
    /// 转换为内核使用的三字节颜色，并夹紧到 0~255。
    ///
    /// Dart 侧传入越界值时不应导致崩溃，因此统一夹紧而非报错。
    pub fn to_rgb(self) -> [u8; 3] {
        [
            self.red.min(255) as u8,
            self.green.min(255) as u8,
            self.blue.min(255) as u8,
        ]
    }
}

/// 图片基础信息（探测用，不做完整解码）。
#[derive(Debug, Clone)]
pub struct ImageInfoDto {
    pub width: u32,
    pub height: u32,
    /// 规范格式名，如 "jpeg"
    pub format: String,
    /// 展示名，如 "JPEG"
    pub format_name: String,
    /// 帧数。非动画格式恒为 1
    pub frame_count: u32,
    /// 输入字节数
    pub byte_size: u64,
    /// 源格式是否支持透明通道（按格式能力给出，非逐像素检测）
    pub source_supports_alpha: bool,
    /// 源格式是否支持动画
    pub source_supports_animation: bool,
}

/// 归一化裁剪框。
#[derive(Debug, Clone, Copy)]
pub struct CropRectDto {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

/// 裁剪参数。
#[derive(Debug, Clone)]
pub struct CropDto {
    /// 证件照规格 id，如 "size_1cun"。给出时会以规格像素作为输出尺寸
    pub preset_id: Option<String>,
    /// 归一化裁剪框。None 且给出 preset_id 时按规格比例自动构图
    pub rect: Option<CropRectDto>,
    /// 目标输出宽度（与高度同时给出时缩放到精确像素）
    pub out_width: Option<u32>,
    /// 目标输出高度
    pub out_height: Option<u32>,
    /// 自动构图的纵向锚点，0~1
    pub vertical_anchor: Option<f32>,
}

/// 换背景参数。
#[derive(Debug, Clone)]
pub struct BackgroundDto {
    /// 目标底色
    pub color: ColorDto,
    /// 背景判定阈值 0~1，默认 0.12
    pub tolerance: Option<f32>,
    /// 软边过渡带宽度（像素），默认 2
    pub feather_px: Option<u32>,
    /// 是否做白底去污染，默认 true
    pub decontaminate: Option<bool>,
    /// 边缘收放 -1~1，默认 0
    pub edge_offset: Option<f32>,
    /// 是否平滑 alpha，默认 true
    pub smooth_alpha: Option<bool>,
}

/// 压缩参数。
#[derive(Debug, Clone)]
pub struct CompressDto {
    /// 体积上限（字节）
    pub target_bytes: Option<u64>,
    /// 长边上限（等比，不放大）
    pub max_long_side: Option<u32>,
    /// JPEG 质量上限，1~100，默认 95
    pub quality_max: Option<u32>,
    /// 可接受的最低质量，默认 85
    pub quality_floor: Option<u32>,
    /// 输出长边下限，默认 200
    pub min_long_side: Option<u32>,
    /// JPEG 是否禁用色度抽样（即 4:4:4），默认 true
    pub jpeg_no_chroma_subsampling: Option<bool>,
    /// PNG 是否使用最高压缩级别，默认 true
    pub png_best_compression: Option<bool>,
}

/// 单张图片的完整处理参数。
#[derive(Debug, Clone)]
pub struct ProcessOptionsDto {
    /// 输出格式，如 "jpg"/"png"/"webp"；None 表示按源格式推断
    pub output_format: Option<String>,
    pub crop: Option<CropDto>,
    pub background: Option<BackgroundDto>,
    pub compress: Option<CompressDto>,
    /// 输出格式不支持透明通道时的压平底色，默认白色
    pub flatten_color: Option<ColorDto>,
    /// 输入为 SVG 且未指定尺寸时的栅格化宽度，默认按 SVG 自带尺寸
    pub svg_render_width: Option<u32>,
}

/// 处理结果（处理失败时通过异常返回，因此此处字段恒为成功态）。
#[derive(Debug, Clone)]
pub struct ProcessResultDto {
    /// 输出文件字节
    pub bytes: Vec<u8>,
    pub width: u32,
    pub height: u32,
    /// 输出格式规范名
    pub format: String,
    /// 输出格式展示名
    pub format_name: String,
    /// 源格式展示名
    pub source_format_name: String,
    /// 最终质量（非质量格式为其质量上限值）
    pub quality: u32,
    /// 最终缩放比例
    pub scale: f32,
    /// 换背景时的背景占比
    pub background_ratio: Option<f32>,
    /// 换背景时的半透明过渡像素占比
    pub feathered_ratio: Option<f32>,
    /// 换背景时检测到的原背景色
    pub detected_background: Option<ColorDto>,
    /// 处理过程说明
    pub notes: Vec<String>,
    /// 需要用户注意的降级提示
    pub warnings: Vec<String>,
}

/// 预设底色选项（名称 + 标准色值）。
#[derive(Debug, Clone)]
pub struct BackgroundChoiceDto {
    pub name: String,
    pub color: ColorDto,
}

/// 证件照规格预设。
#[derive(Debug, Clone)]
pub struct PresetDto {
    pub id: String,
    pub name: String,
    /// 分类规范名
    pub category: String,
    /// 分类展示名
    pub category_name: String,
    pub width_mm: f32,
    pub height_mm: f32,
    pub width_px: u32,
    pub height_px: u32,
    pub dpi: u32,
    /// 常用底色展示名
    pub background_names: Vec<String>,
    /// 常用底色色值
    pub background_colors: Vec<ColorDto>,
    /// 备注（用途与额外限制）
    pub note: String,
}

/// 批量处理输入项。
#[derive(Debug, Clone)]
pub struct BatchItemDto {
    /// 调用方自定义的稳定标识，用于把进度回报对应回列表行
    pub id: String,
    pub bytes: Vec<u8>,
    pub filename: Option<String>,
}

/// 批量处理进度回报。
#[derive(Debug, Clone)]
pub struct BatchProgressDto {
    /// 该输入项在提交列表中的下标
    pub index: u32,
    /// 调用方标识，原样回传
    pub id: String,
    /// 累计完成数（含成功与失败）
    pub done: u32,
    /// 总任务数
    pub total: u32,
    /// 累计成功数
    pub succeeded: u32,
    /// 累计失败数
    pub failed: u32,
    /// 成功时的处理结果
    pub result: Option<ProcessResultDto>,
    /// 失败时的错误信息
    pub error: Option<String>,
}
