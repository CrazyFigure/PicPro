//! PicPro 图像处理内核。
//!
//! 本 crate 是纯计算层，不含任何平台相关的 IO 或 UI 逻辑，
//! 因此可以同时编译为：
//! - **原生动态库**：Windows / Android 经 FFI 调用；
//! - **WASM**：Web 端在浏览器内直接运行。
//!
//! 处理流水线的固定顺序（顺序不可颠倒）：
//! 解码 → 裁剪到目标规格 → 换背景 → 按目标体积压缩 → 编码输出。
//!
//! 之所以必须先裁后压：证件照的体积要求是在**规定像素**下考核的，
//! 若先压体积再裁剪，裁完体积会再次变化，需要重复压缩。

/// Flutter ↔ Rust 的 FFI 接口层。
///
/// `flutter_rust_bridge.yaml` 中的 `rust_input: crate::api` 指向本模块，
/// 因此这里所有公开项都会被生成 Dart 绑定。
pub mod api;

/// FRB 生成的胶水代码，包含 StreamSink 等运行时类型。
mod frb_generated;

pub mod core;

/// 便于外部使用的常用类型再导出。
///
/// 这里不额外再导出 `PicProError`：它属于 `crate::core::error` 的职责，
/// 需要时按完整路径引用即可，避免 crate 根命名空间被错误类型占满。
pub use crate::core::format::ImageFormat;
pub use crate::core::types::{Frame, RasterImage};

/// 内核版本号，供界面展示与问题排查。
pub const CORE_VERSION: &str = env!("CARGO_PKG_VERSION");
