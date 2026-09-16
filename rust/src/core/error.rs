//! 错误类型定义。
//!
//! 统一错误枚举便于 FFI 层把错误转成可读文案返回给界面，
//! 同时让上层能区分「可提示用户调整参数」与「真正的失败」。

use thiserror::Error;

/// PicPro 处理内核的统一错误类型。
///
/// 本类型会经 FFI 导出为 Dart 异常类，因此**变体结构需保持稳定**：
/// 每个变体都只携带一个字符串，Dart 侧据此生成对应的异常子类，
/// 界面可据此区分「需用户调整参数」的错误（如 `TargetUnreachable`）
/// 与其他失败，而不是只拿到一句无法判断的文案。
#[derive(Debug, Error)]
pub enum PicProError {
    /// 无法识别输入格式（魔数与扩展名都不匹配已知类型）
    #[error("无法识别的图片格式：{0}")]
    UnknownFormat(String),

    /// 输入声明为某格式但实际内容不符，或该格式不支持该操作
    #[error("格式不支持：{0}")]
    UnsupportedFormat(String),

    /// 解码失败
    #[error("图片解码失败：{0}")]
    Decode(String),

    /// 编码失败
    #[error("图片编码失败：{0}")]
    Encode(String),

    /// SVG 栅格化失败
    #[error("SVG 渲染失败：{0}")]
    Svg(String),

    /// 文件读写失败
    #[error("文件读写失败：{0}")]
    Io(String),

    /// 在给定约束（体积上限 / 分辨率下限）下无法达成目标，
    /// 属于「用户可调整参数解决」的失败，界面应提示放宽约束
    #[error("在给定约束下无法达成目标：{0}")]
    TargetUnreachable(String),

    /// 参数非法
    #[error("参数非法：{0}")]
    InvalidArgument(String),
}

impl From<std::io::Error> for PicProError {
    fn from(e: std::io::Error) -> Self {
        PicProError::Io(e.to_string())
    }
}

impl From<image::ImageError> for PicProError {
    fn from(e: image::ImageError) -> Self {
        use image::ImageError::*;
        match e {
            // 解码类错误单独归类，便于界面区分「文件损坏」与「写出失败」
            Decoding(_) | Unsupported(_) => PicProError::Decode(e.to_string()),
            Encoding(_) => PicProError::Encode(e.to_string()),
            _ => PicProError::Decode(e.to_string()),
        }
    }
}

/// 内核统一 Result 别名。
pub type Result<T> = std::result::Result<T, PicProError>;
