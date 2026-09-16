/// 文件名处理工具。
///
/// 独立成文件是为了让三端实现与上层业务都能复用同一套规则，
/// 避免在原生实现与门面之间产生循环依赖。
library;

/// 清理文件名中的非法字符。
///
/// 输出文件名由「原文件名 + 用户后缀 + 新扩展名」拼出，用户也可能自定义后缀，
/// 其中可能含 Windows 保留字符（\ / : * ? " < > |）或控制字符，
/// 直接写盘会抛异常并中断整批导出，因此统一在写盘前清理。
String sanitizeFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  // 清理后可能变空（原名全由非法字符组成），给一个兜底名避免写出空文件名
  if (cleaned.isEmpty || cleaned == '_') return 'output';
  return cleaned;
}
