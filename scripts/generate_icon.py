# -*- coding: utf-8 -*-
"""
生成 PicPro 应用图标主图（1024×1024 PNG）。

设计取舍：
- 用几何图形而非生成式图像：应用图标需要在 16×16 到 256×256 之间都清晰，
  图形越简洁、边缘越锐利，小尺寸下的可辨识度越高。
- 蓝色圆角方块 + 白色「图片」符号：直接表达「图片工具」，
  且与界面主色（#2F6FEB）一致，视觉上成体系。
- 4 倍超采样后缩小：PIL 的圆角与圆形没有抗锯齿，超采样是获得平滑边缘的可靠办法。
"""

import os

from PIL import Image, ImageDraw

SIZE = 1024
SS = 4  # 超采样倍数
S = SIZE * SS

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets")
OUT_PNG = os.path.join(OUT_DIR, "app_icon.png")

# 与界面主色一致的蓝色渐变端点
BLUE_TOP = (91, 155, 243)
BLUE_BOTTOM = (47, 111, 235)
WHITE = (255, 255, 255)


def rounded_mask(size: int, radius: int) -> Image.Image:
    """生成圆角矩形遮罩。"""
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def vertical_gradient(size: int, top: tuple, bottom: tuple) -> Image.Image:
    """生成垂直渐变底。"""
    grad = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(1, size - 1)
        grad.putpixel(
            (0, y),
            (
                round(top[0] + (bottom[0] - top[0]) * t),
                round(top[1] + (bottom[1] - top[1]) * t),
                round(top[2] + (bottom[2] - top[2]) * t),
            ),
        )
    return grad.resize((size, size), Image.NEAREST)


def build_icon() -> Image.Image:
    """绘制图标：蓝底圆角方块 + 白色图片符号。"""
    # 背景：渐变 + 圆角遮罩
    bg = vertical_gradient(S, BLUE_TOP, BLUE_BOTTOM).convert("RGBA")
    bg.putalpha(rounded_mask(S, int(S * 0.225)))

    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    # 图片外框：居中圆角方框，用描边而非填充，留出内部空间放图形
    margin = int(S * 0.235)
    stroke = int(S * 0.062)
    box = [margin, margin + int(S * 0.01), S - margin, S - margin - int(S * 0.01)]
    d.rounded_rectangle(
        box,
        radius=int(S * 0.075),
        outline=WHITE,
        width=stroke,
    )

    # 内区（用于裁剪图形，保证不超出边框内侧）
    inner = [
        box[0] + stroke,
        box[1] + stroke,
        box[2] - stroke,
        box[3] - stroke,
    ]

    # 太阳：左上角实心圆
    sun_r = int(S * 0.052)
    sun_cx = inner[0] + int(S * 0.105)
    sun_cy = inner[1] + int(S * 0.105)
    d.ellipse(
        [sun_cx - sun_r, sun_cy - sun_r, sun_cx + sun_r, sun_cy + sun_r],
        fill=WHITE,
    )

    # 山峦：两座三角形，底边与内区齐平
    inner_w = inner[2] - inner[0]
    inner_h = inner[3] - inner[1]
    base_y = inner[3]
    # 主峰
    d.polygon(
        [
            (inner[0] + int(inner_w * 0.20), base_y),
            (inner[0] + int(inner_w * 0.50), inner[1] + int(inner_h * 0.34)),
            (inner[0] + int(inner_w * 0.80), base_y),
        ],
        fill=WHITE,
    )
    # 副峰，略矮，增加层次
    d.polygon(
        [
            (inner[0] + int(inner_w * 0.52), base_y),
            (inner[0] + int(inner_w * 0.74), inner[1] + int(inner_h * 0.55)),
            (inner[0] + int(inner_w * 0.96), base_y),
        ],
        fill=WHITE,
    )

    out = Image.alpha_composite(bg, layer)
    # 超采样缩小，获得平滑边缘
    return out.resize((SIZE, SIZE), Image.LANCZOS)


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    icon = build_icon()
    icon.save(OUT_PNG)
    print(f"已生成 {OUT_PNG}  {icon.size[0]}x{icon.size[1]}")
