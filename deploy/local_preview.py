# -*- coding: utf-8 -*-
"""
本地预览服务器：模拟 deploy/nginx.conf 的响应头行为。

用途：在本地验证 Web 产物能否真正运行。
关键在于必须发送 COOP/COEP 两个响应头——Rust 内核是多线程 WASM，
依赖 SharedArrayBuffer，而浏览器只在跨源隔离状态下才允许使用它。
Python 自带的 http.server 不发这些头，直接用会导致页面加载失败，
因此这里做一层包装。

同时补上 .wasm 的 MIME 类型（Python 的 mimetypes 未必内置）。
"""

import functools
import http.server
import mimetypes
import os
import socketserver
import sys

PORT = 8123
# 本脚本位于 <项目根>/deploy/，因此项目根要向上回退一级。
# 允许通过命令行参数覆盖，便于脚本被移动后仍可使用。
_DEFAULT_ROOT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "build",
    "web",
)
ROOT = sys.argv[1] if len(sys.argv) > 1 else _DEFAULT_ROOT

# 确保 .wasm 被识别为 application/wasm，否则浏览器会禁用流式编译
mimetypes.add_type("application/wasm", ".wasm")


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # 跨源隔离：多线程 WASM 的硬性前提
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        # 本地验证时不缓存，避免改完看不到效果
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        # 只记录错误，避免静态请求刷屏
        if str(args[1] if len(args) > 1 else "").startswith(("4", "5")):
            super().log_message(fmt, *args)


if __name__ == "__main__":
    handler = functools.partial(Handler, directory=ROOT)
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", PORT), handler) as httpd:
        print(f"serving {ROOT} at http://127.0.0.1:{PORT}")
        httpd.serve_forever()
