# -*- coding: utf-8 -*-
"""
从图标主图生成各平台所需的图标资源。

产出：
1. installers/installer.ico            —— NSIS 安装包图标
2. windows/runner/resources/app_icon.ico —— Windows 应用图标（PE 资源）
3. android/app/src/main/res/mipmap-*/ic_launcher.png —— Android 启动图标

要点：
- ICO 必须包含 7 个尺寸（16/24/32/48/64/128/256），
  缺少小尺寸会导致任务栏、Alt-Tab、任务管理器出现模糊的缩放结果。
- Pillow 在 sizes 含 256 时会自动用 PNG-in-ICO 编码，体积更小且质量更高。
- 主图已带透明通道（圆角外为透明），无需再做白底转透明处理。
"""

import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "app_icon.png")

ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]

# Android 各密度对应的启动图标边长
ANDROID_MIPMAPS = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


def build_ico(src: Image.Image, out_path: str) -> None:
    """生成多分辨率 ICO。"""
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    # 传入元组列表，Pillow 会为每个尺寸单独生成一帧
    src.save(out_path, format="ICO", sizes=[(s, s) for s in ICO_SIZES])
    size_kb = os.path.getsize(out_path) / 1024
    print(f"  已生成 {os.path.relpath(out_path, ROOT)}  {size_kb:.1f} KB")


def build_android_icons(src: Image.Image) -> None:
    """生成 Android 各密度的启动图标。"""
    for folder, px in ANDROID_MIPMAPS.items():
        out_dir = os.path.join(ROOT, "android", "app", "src", "main", "res", folder)
        os.makedirs(out_dir, exist_ok=True)
        resized = src.resize((px, px), Image.LANCZOS)
        out = os.path.join(out_dir, "ic_launcher.png")
        resized.save(out)
        print(f"  已生成 {os.path.relpath(out, ROOT)}  {px}x{px}")


def main() -> None:
    if not os.path.exists(SRC):
        raise SystemExit(f"找不到图标主图：{SRC}\n请先运行 scripts/generate_icon.py")

    src = Image.open(SRC).convert("RGBA")
    if src.width != src.height:
        raise SystemExit(f"图标主图必须是正方形，当前为 {src.size}")

    print(f"主图 {src.size[0]}x{src.size[1]}")

    # NSIS 安装包图标
    build_ico(src, os.path.join(ROOT, "installers", "installer.ico"))
    # Windows 应用图标（Runner.rc 已引用该路径）
    build_ico(src, os.path.join(ROOT, "windows", "runner", "resources", "app_icon.ico"))
    # Android 启动图标
    build_android_icons(src)

    print("完成")


if __name__ == "__main__":
    main()
