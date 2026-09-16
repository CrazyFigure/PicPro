//! 内核各功能模块。
//!
//! 模块划分按「处理阶段」而非「数据类型」，与流水线顺序一一对应，
//! 便于定位问题出在哪个环节：
//!
//! - [`error`]：统一错误类型
//! - [`format`]：格式识别与能力查询（决定后续能做什么）
//! - [`types`]：统一内存图像表示
//! - [`decode`]：各格式 → 统一表示
//! - [`resize`]：高质量重采样（裁剪与压缩共用）
//! - [`crop`]：按规格预设裁剪
//! - [`background`]：背景识别、抠图与换色
//! - [`compress`]：按目标体积搜索参数
//! - [`encode`]：统一表示 → 各格式
//! - [`presets`]：证件照规格预设库
//! - [`pipeline`]：把上述步骤串成完整流水线

pub mod background;
pub mod compress;
pub mod crop;
pub mod decode;
pub mod encode;
pub mod error;
pub mod format;
pub mod pipeline;
pub mod presets;
pub mod resize;
pub mod types;
