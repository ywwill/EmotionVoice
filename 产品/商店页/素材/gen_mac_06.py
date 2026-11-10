#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
macOS 预览图 06「我的项目 / Projects」—— 换成当前播放器界面的真机窗口图。

背景：旧 06 的窗口图还是早期播放器（上一首/下一首、时长/格式/大小/音色四宫格），
现在是「我的项目列表 + 右侧播放器（大波形 / 15s·5s 跳转 / 1x / 逐句稿件）」。
用户要求**在原有文件上直接替换** 06，不动 01–05。

做法：只换 `html/<lang>/06.html` 引用的窗口图 `win-06.png` 与 `.win` 的框高，
其余 CSS、标题文案、`.win` 宽度、画布尺寸全部保持原样。

用法：
  python3 gen_mac_06.py --step src        # 把上传截图归档成 06-src.png
  python3 gen_mac_06.py --step win        # 生成 html/<lang>/win-06.png（2112 宽）
  python3 gen_mac_06.py --step html       # 改 06.html 的 .win 高度
  python3 gen_mac_06.py --step export     # 渲染 2880x1800 并覆盖 mac-2880x1800/<lang>/06-*
  python3 gen_mac_06.py                   # 以上全跑
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
CANVAS = (2880, 1800)
WIN_W = 2112                      # 与 01–05 同宽，整组窗口体量一致
SRC_DIR = os.path.join(HERE, "mac-06-src")
LANGS = ["zh", "en", "zh-Hant"]
OUT = {
    "zh": os.path.join(HERE, "mac-2880x1800", "zh", "06-我的项目.png"),
    "en": os.path.join(HERE, "mac-2880x1800", "en", "06-Projects.png"),
    "zh-Hant": os.path.join(HERE, "mac-2880x1800", "zh-Hant", "06-我的項目.png"),
}
ACTIVE = list(LANGS)              # 由 --lang 收窄，见 main()
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


def src_step() -> None:
    """把用户上传的两张截图归档成 PNG（源文件在剪贴板目录，会被清理）。"""
    files = {
        "zh": "/Users/young/.workbuddy/clipboard-images/clipboard-2026-11-10T08-46-02-294Z-e989f089.jpg",
        "en": "/Users/young/.workbuddy/clipboard-images/clipboard-2026-11-10T08-46-02-295Z-2958c5d5.jpg",
        "zh-Hant": "/Users/young/.workbuddy/clipboard-images/clipboard-2026-11-10T11-07-54-862Z-f34eef91.jpg",
    }
    for lang, path in files.items():
        d = os.path.join(SRC_DIR, lang)
        os.makedirs(d, exist_ok=True)
        im = Image.open(path).convert("RGB")
        im.save(os.path.join(d, "06-src.png"))
        print(f"[src] {lang}: {im.size}")


def win_h(lang: str) -> int:
    im = Image.open(os.path.join(SRC_DIR, lang, "06-src.png"))
    return round(WIN_W * im.height / im.width)


def win_step() -> None:
    for lang in ACTIVE:
        im = Image.open(os.path.join(SRC_DIR, lang, "06-src.png")).convert("RGB")
        h = win_h(lang)
        # 预缩放成窗口的最终像素尺寸，浏览器里 1:1 贴图（比 CSS 缩放锐）
        im = im.resize((WIN_W, h), Image.LANCZOS)
        dst = os.path.join(HERE, "html", lang, "win-06.png")
        im.save(dst)
        print(f"[win] {lang}: {im.size} -> html/{lang}/win-06.png")


def html_step() -> None:
    for lang in ACTIVE:
        p = os.path.join(HERE, "html", lang, "06.html")
        s = open(p, encoding="utf-8").read()
        h = win_h(lang)
        s2 = re.sub(r'(class="win" style="width:2112px;height:)\d+(px")',
                    rf"\g<1>{h}\g<2>", s)
        if s2 == s:
            print(f"[html] {lang}: 已是 height:{h}px，未改动")
        else:
            open(p, "w", encoding="utf-8").write(s2)
            print(f"[html] {lang}: .win 高度 -> {h}px")


def export_step() -> None:
    for i, lang in enumerate(ACTIVE):
        page = os.path.join(HERE, "html", lang, "06.html")
        tmp = f"/tmp/mac06-{lang}-{os.getpid()}.png"
        profile = f"/tmp/mac06-profile-{os.getpid()}-{i}"
        cmd = [
            CHROME, "--headless=new",
            # 当前环境的进程沙箱不允许 Chrome 起自己的 sandbox（否则 SIGTRAP）
            "--no-sandbox", "--disable-gpu", "--hide-scrollbars",
            "--force-device-scale-factor=1",
            f"--window-size={CANVAS[0]},{CANVAS[1]}",
            "--virtual-time-budget=3000",
            f"--user-data-dir={profile}",
            f"--screenshot={tmp}",
            "file://" + page,
        ]
        # ⚠️ headless 偶发「视口最后 21px 没画完」→ 底部白条（不同次导出 md5 会变）。
        # 出图后检查底部 24px 的亮度，出现近白就重渲，最多 4 次。
        for attempt in range(4):
            subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            im = Image.open(tmp).convert("RGB")   # App Store 不接受 alpha
            bottom = im.crop((0, im.height - 24, im.width, im.height)).convert("L")
            if bottom.getextrema()[1] < 200:
                break
            print(f"[export] {lang}: 底部出现未绘制白条，重渲（第 {attempt + 2} 次）")
        assert im.size == CANVAS, f"{lang} 尺寸异常 {im.size}"
        # 最底部 24 行统一成上一行：这一带本来就是近似纯色的渐变底，
        # 而 headless 有时只画到 height-21，会留一条肉眼几乎看不出、但让 md5 每次都变的色带。
        row = im.crop((0, im.height - 25, im.width, im.height - 24))
        for y in range(im.height - 24, im.height):
            im.paste(row, (0, y))
        im.save(OUT[lang])
        os.remove(tmp)
        shutil.rmtree(profile, ignore_errors=True)
        print(f"[export] {lang}: {OUT[lang]} {im.size}")


def main() -> None:
    global ACTIVE
    ap = argparse.ArgumentParser()
    ap.add_argument("--step", default="all", choices=["src", "win", "html", "export", "all"])
    ap.add_argument("--lang", default="all", help="只处理某一语（zh / en / zh-Hant）")
    a = ap.parse_args()
    if a.lang != "all":
        if a.lang not in LANGS:
            ap.error(f"未知语言 {a.lang}")
        ACTIVE = [a.lang]
    if a.step in ("src", "all"):
        src_step()
    if a.step in ("win", "all"):
        win_step()
    if a.step in ("html", "all"):
        html_step()
    if a.step in ("export", "all"):
        export_step()


if __name__ == "__main__":
    sys.exit(main())
