# -*- coding: utf-8 -*-
"""
本地预览服务器：尽量贴近 deploy/nginx.conf 的响应头行为。

用途：在本地验证 Web 产物能否真正运行。
同时发送 COOP/COEP 两个跨源隔离响应头，以便在 localhost 下复现
「跨源隔离可用」的环境；而绑到局域网地址再访问时，浏览器会把该来源
视为非可信来源并忽略这两个头，于是可以复现「纯 HTTP 公网访问」的行为。

同时补上 .wasm 的 MIME 类型（Python 的 mimetypes 未必内置）。

用法：
    python local_preview.py [站点根目录] [监听地址] [端口]

监听地址默认 127.0.0.1：
    python local_preview.py "" 0.0.0.0 8200
    # 浏览器打开 http://<本机局域网IP>:8200 即为「非安全来源」场景
"""

import functools
import http.server
import mimetypes
import os
import socketserver
import sys

# 本脚本位于 <项目根>/deploy/，因此项目根要向上回退一级。
_DEFAULT_ROOT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "build",
    "web",
)
ROOT = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else _DEFAULT_ROOT
HOST = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1"
PORT = int(sys.argv[3]) if len(sys.argv) > 3 else 8123

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
    # 用 ThreadingTCPServer：浏览器会并发拉取多个资源，单线程会互相阻塞
    class Server(socketserver.ThreadingTCPServer):
        daemon_threads = True

    with Server((HOST, PORT), handler) as httpd:
        print(f"serving {ROOT} at http://{HOST}:{PORT}")
        if HOST == "0.0.0.0":
            print("（绑定了所有网卡，可用本机局域网 IP 访问以复现非安全来源的行为）")
        httpd.serve_forever()
