"""生成集成测试用的合成人像图。

只用标准库写出 PNG，避免为测试引入 Pillow 依赖；产物写入 build/test_assets/，
该目录已被 .gitignore 忽略——不做成仓库里的二进制附件，是为了让测试素材
可复现、可审查，也避免仓库无谓膨胀。

用法（跑 integration_test 之前执行一次即可）：
    python scripts/gen_test_assets.py
"""
import math
import os
import struct
import zlib

# 本脚本位于 <项目根>/scripts/，产物统一落到 <项目根>/build/test_assets/
_OUT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(_OUT_ROOT, "build", "test_assets")
os.makedirs(OUT_DIR, exist_ok=True)


def write_png(path, w, h, pixel_fn):
    raw = bytearray()
    for y in range(h):
        raw.append(0)  # 每行过滤器固定为 None，简化实现
        for x in range(w):
            r, g, b = pixel_fn(x, y)
            raw += bytes((r, g, b))

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 6))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)
    print("wrote", path, os.path.getsize(path), "bytes")


def portrait(w, h):
    """浅色背景 + 深色头发/西装 + 肤色人脸的合成人像，用于换背景与裁剪测试。"""
    cx = w / 2.0
    # 各部位按图像高度比例定义，保证换分辨率后构图一致
    head_cy = h * 0.32
    head_rx = w * 0.155
    head_ry = h * 0.155
    shoulder_top = h * 0.62

    def px(x, y):
        # 背景：接近纯白但带极轻微噪声，模拟真实拍摄的非理想均匀背景
        n = ((x * 7 + y * 13) % 5) - 2
        bg = (246 + n, 246 + n, 248 + n)

        if y >= shoulder_top:
            # 肩部/西装：深色，宽度随高度线性展开
            t = (y - shoulder_top) / max(1.0, h - shoulder_top)
            half = w * (0.20 + 0.28 * t)
            if abs(x - cx) <= half:
                shade = 34 + int(10 * t)
                return (shade, shade + 2, shade + 6)

        # 头部：椭圆范围
        nx = (x - cx) / head_rx
        ny = (y - head_cy) / head_ry
        d = nx * nx + ny * ny
        if d <= 1.0:
            # 上部一圈当作头发，其余为肤色
            if d > 0.62 or y < head_cy - head_ry * 0.25:
                return (40, 34, 30)
            return (228, 186, 156)

        return bg

    return px


for name, (w, h) in {
    "portrait_600x800.png": (600, 800),
    "portrait_900x1200.png": (900, 1200),
    "portrait_1200x900.png": (1200, 900),
    # 12MP：模拟手机直出照片，用于验证预览与处理在真实尺寸下是否卡死界面
    "photo_3000x4000.png": (3000, 4000),
}.items():
    write_png(os.path.join(OUT_DIR, name), w, h, portrait(w, h))
