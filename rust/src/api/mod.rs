//! Flutter ↔ Rust 的 FFI 接口层。
//!
//! 该模块只做「DTO ↔ 内核类型」的映射与参数校验，不含业务算法，
//! 所有实际处理都在 [`crate::core::pipeline`] 中完成，以便脱离 FFI 测试。
//!
//! 命名与类型约定：
//! - 数值字段统一用 `u32`/`f32`/`u64` 而非 `u8`，减少跨语言类型映射的歧义，
//!   转换时统一做范围夹紧；
//! - 可选参数一律用 `Option`，未传即使用内核默认值，
//!   避免在 Dart 侧重复维护一套默认值。

pub mod dto;
pub mod image_api;

/// FRB 初始化入口，由 Dart 侧在应用启动时调用一次。
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // 安装默认的日志与 panic 处理，便于定位内核侧问题
    flutter_rust_bridge::setup_default_user_utils();
}
