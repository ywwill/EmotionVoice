#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
iOS 预览图 05（播放界面）—— 用真机截图合成 1320×2868 商店图。

背景：原来的 `ios-1320x2868/<lang>/05-shot-favorite.png` 是早期播放器 UI
（上一首/下一首、1.0x、时长/格式/大小/音色四宫格），现在播放器是
大波形 + 15s/5s 跳转 + 倍速 + 逐字高亮跟读 + 句子卡片点句跳转。

⚠️ 2026-11-10 起**直接覆盖** `ios-1320x2868/<lang>/05-shot-favorite.png`（保持文件名不变，
用户已把这一版采纳为正式图）；中间产物仍留在 `ios-05v2/` 下，方便换图重做。

目录：
  src/<lang>/05-playback-src.png   原始截图（885x1920，归档）
  raw/<lang>/05-playback.png       预缩放成 1007x2214（设备屏幕 1:1 像素）
  html/<lang>/05.html              合成页（1320x2868）
  成片 → ios-1320x2868/<lang>/05-shot-favorite.png（1320x2868，RGB 无 alpha）

用法：python3 gen_ios_05_v2.py [--step ...] [--lang zh-Hant]
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "ios-05v2")

LANGS = ["zh-Hans", "en-US", "zh-Hant"]
OUT = {l: os.path.join(HERE, "ios-1320x2868", l, "05-shot-favorite.png") for l in LANGS}
ACTIVE = list(LANGS)          # 由 --lang 收窄，见 main()

# 设备屏幕在合成页里的 CSS 像素尺寸（.device 1033x2240 - padding 13*2）。
# 视口 1320x2868 / DPR 1 ⇒ CSS 像素 == 设备像素，预缩放到这个尺寸即 1:1，不糊。
SCREEN_W, SCREEN_H = 1007, 2214
CANVAS_W, CANVAS_H = 1320, 2868

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

COPY = {
    "zh-Hans": {
        "lang": "zh-CN",
        "h1": ("边听边跟读，", "点哪句听哪句"),
        "sub": "逐字高亮跟读，15 秒快进、倍速、点句跳转",
        "font": "  font-family:-apple-system,'PingFang SC','Helvetica Neue',sans-serif;\n",
        "extra": "",
        "img": "../../raw/zh-Hans/05-playback.png",
    },
    "zh-Hant": {
        "lang": "zh-Hant",
        "h1": ("邊聽邊跟讀，", "點哪句聽哪句"),
        "sub": "逐字跟讀標示，15 秒快進、倍速、點句跳轉",
        "font": "  font-family:-apple-system,'PingFang SC','Helvetica Neue',sans-serif;\n",
        # 繁体页必须 PingFang TC：H1 的「讀」在 SC 字体下会渲染成简体字形
        "extra": (
            "\n/* 繁体页改用 PingFang TC：H1 里「讀」「邊」「點」不能用简体字形渲染 */\n"
            "body,h1,.sub{font-family:-apple-system,'PingFang TC','PingFang HK','Helvetica Neue',\n"
            "  sans-serif!important}\n"
        ),
        "img": "../../raw/zh-Hant/05-playback.png",
    },
    "en-US": {
        "lang": "en",
        "h1": ("Listen and follow,", "jump to any line"),
        "sub": "Word-by-word highlight, 15s skip, speed, tap-to-jump",
        "font": "  font-family:-apple-system,'PingFang SC','Helvetica Neue',sans-serif;\n",
        "extra": (
            "\n/* 英文页走 Helvetica 栈，PingFang 的拉丁字形偏窄 */\n"
            "body,h1,.sub{font-family:-apple-system,'Helvetica Neue',Helvetica,Arial,sans-serif!important}\n"
        ),
        "img": "../../raw/en-US/05-playback.png",
    },
}

HTML = """<!DOCTYPE html><html lang="{lang}"><head><meta charset="utf-8">
<style>
*{{margin:0;padding:0;box-sizing:border-box}}
body{{width:{cw}px;height:{ch}px;overflow:hidden;position:relative;
{font}  background:radial-gradient(1000px 780px at 88% 4%,rgba(138,91,255,.17),transparent 62%),
             radial-gradient(820px 700px at 2% 42%,rgba(255,95,162,.11),transparent 60%),
             radial-gradient(760px 640px at 96% 90%,rgba(46,217,191,.12),transparent 62%),
             linear-gradient(165deg,#F8F5FF 0%,#FFFFFF 52%,#F3EFFC 100%)}}
.head{{position:absolute;left:120px;right:120px;top:36px}}
h1{{font-size:106px;font-weight:800;line-height:1.22;
   letter-spacing:-2px;color:#1B1533}}
h1 em{{font-style:normal;background:linear-gradient(100deg,#5B2EDB,#CE2B72);
      -webkit-background-clip:text;background-clip:text;color:transparent}}
.sub{{margin-top:24px;font-size:42px;line-height:1.5;color:#5C5780;letter-spacing:.5px}}
.stage{{position:absolute;left:0;right:0;top:538px;display:flex;justify-content:center}}
.device{{position:relative;width:1033px;height:2240px;border-radius:112px;padding:13px;
  background:linear-gradient(150deg,#FFFFFF,#E9E3F8);
  box-shadow:0 60px 140px rgba(60,30,130,.20),0 8px 30px rgba(60,30,130,.10),
             inset 0 0 0 2px rgba(255,255,255,.92)}}
.screen{{width:100%;height:100%;border-radius:99px;overflow:hidden;
        position:relative;background:#F5F1FE}}
.screen img{{width:100%;height:100%;display:block;object-fit:cover}}
.dots{{position:absolute;left:0;right:0;bottom:40px;display:flex;
      justify-content:center;gap:16px}}
.dots i{{width:14px;height:14px;border-radius:999px;background:#D8CFEE;display:block}}
.dots i.on{{width:46px;background:linear-gradient(90deg,#5B2EDB,#CE2B72)}}
{extra}</style></head><body>
<div class="head">
  <h1>{l1}<br><em>{l2}</em></h1>
  <div class="sub">{sub}</div>
</div>
<div class="stage"><div class="device">
  <div class="screen"><img src="{img}"></div>
</div></div>
<div class="dots"><i class=""></i><i class=""></i><i class=""></i><i class=""></i><i class="on"></i><i class=""></i></div>
</body></html>"""


def prepare() -> None:
    for lang in ACTIVE:
        src = os.path.join(WORK, "src", lang, "05-playback-src.png")
        im = Image.open(src).convert("RGB")
        # cover：等比放大到刚好盖住屏幕，再居中裁掉多出的窄边（不拉伸变形）
        scale = max(SCREEN_W / im.width, SCREEN_H / im.height)
        w, h = round(im.width * scale), round(im.height * scale)
        im = im.resize((w, h), Image.LANCZOS)
        left, top = (w - SCREEN_W) // 2, (h - SCREEN_H) // 2
        im = im.crop((left, top, left + SCREEN_W, top + SCREEN_H))
        out = os.path.join(WORK, "raw", lang)
        os.makedirs(out, exist_ok=True)
        im.save(os.path.join(out, "05-playback.png"))
        print(f"[prepare] {lang}: {im.size}")


def statusbar() -> None:
    """把状态栏时间统一成 9:41（Apple 惯例），与同组其它 5 张保持一致。

    三张原图分别是 15:53 / 16:01 / 15:59，同组里会显得是三次不同时刻的抓拍。
    状态栏底色实测是纯平的 #F5F1FF（sd=0），所以整块刷底再重绘不会留补丁；
    字号按「原文字墨迹高度 == 新文字墨迹高度」反解，字重用 SFNS Semibold，
    左边与顶边对齐到原墨迹框，避免位置漂移。
    """
    from PIL import ImageDraw, ImageFont, ImageStat

    font_path = "/System/Library/Fonts/SFNS.ttf"
    for lang in ACTIVE:
        path = os.path.join(WORK, "raw", lang, "05-playback.png")
        im = Image.open(path).convert("RGB")
        probe = (80, 20, 320, 120)
        reg = im.crop(probe).convert("L").point(lambda v: 255 if v < 100 else 0)
        bb = reg.getbbox()
        if not bb:
            print(f"[statusbar] {lang}: 没找到时间文字，跳过")
            continue
        box = (bb[0] + probe[0], bb[1] + probe[1], bb[2] + probe[0], bb[3] + probe[1])
        h = box[3] - box[1]
        bg = tuple(int(round(v)) for v in ImageStat.Stat(im.crop((80, 0, 320, box[1] - 6))).mean)

        def ink_h(size: int) -> int:
            ff = ImageFont.truetype(font_path, size)
            ff.set_variation_by_name("Semibold")
            b = ff.getbbox("9:41")
            return b[3] - b[1]

        size = min(range(int(h * 1.02), int(h * 1.9)), key=lambda s: abs(ink_h(s) - h))
        f = ImageFont.truetype(font_path, size)
        f.set_variation_by_name("Semibold")

        d = ImageDraw.Draw(im)
        d.rectangle((box[0] - 8, box[1] - 8, box[2] + 8, box[3] + 8), fill=bg)
        # 单独渲染再按墨迹对齐，避免字体 side bearing 让文字整体偏移
        tmp = Image.new("RGB", (300, 120), bg)
        ImageDraw.Draw(tmp).text((30, 30), "9:41", font=f, fill=(0, 0, 0))
        ink = tmp.convert("L").point(lambda v: 255 if v < 100 else 0).getbbox()
        im.paste(tmp.crop(ink), (box[0], box[1]))
        im.save(path)
        print(f"[statusbar] {lang}: {box} h={h} size={size} bg={bg}")


def build_html() -> None:
    for lang in ACTIVE:
        cfg = COPY[lang]
        html = HTML.format(
            lang=cfg["lang"],
            cw=CANVAS_W,
            ch=CANVAS_H,
            font=cfg["font"],
            extra=cfg["extra"],
            l1=cfg["h1"][0],
            l2=cfg["h1"][1],
            sub=cfg["sub"],
            img=cfg["img"],
        )
        out = os.path.join(WORK, "html", lang)
        os.makedirs(out, exist_ok=True)
        with open(os.path.join(out, "05.html"), "w", encoding="utf-8") as f:
            f.write(html)
        print(f"[html] {lang}: {len(html)} bytes")


def export() -> None:
    for i, lang in enumerate(ACTIVE):
        page = os.path.join(WORK, "html", lang, "05.html")
        tmpdir = os.path.join(WORK, "out")
        os.makedirs(tmpdir, exist_ok=True)
        png = os.path.join(tmpdir, f"_{lang}-raw.png")
        profile = f"/tmp/ios05v2-profile-{os.getpid()}-{i}"
        cmd = [
            CHROME,
            "--headless=new",
            # 当前环境的进程沙箱不允许 Chrome 起自己的 sandbox（SIGTRAP / GPU process isn't usable）
            "--no-sandbox",
            "--disable-gpu",
            "--hide-scrollbars",
            "--force-device-scale-factor=1",
            f"--window-size={CANVAS_W},{CANVAS_H}",
            "--virtual-time-budget=3000",
            f"--user-data-dir={profile}",
            f"--screenshot={png}",
            "file://" + page,
        ]
        # ⚠️ headless 偶发「视口最后 21px 没画完」→ 底部纯白条（Mac 那套实测 1/4 概率）。
        # 出图后检查底部 6 行有没有整行近白，有就重渲，最多 4 次。
        for _ in range(4):
            subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            im = Image.open(png).convert("RGB")   # App Store 不接受带 alpha
            # 整行都接近纯白 ⇒ 这一条是没画出来的白底（正常底色最亮也只到 ~243）
            if im.crop((0, im.height - 6, im.width, im.height)).convert("L").getextrema()[0] < 248:
                break
            print(f"[export] {lang}: 底部未画完（白条），重渲")
        assert im.size == (CANVAS_W, CANVAS_H), f"{lang} 尺寸异常 {im.size}"
        os.makedirs(os.path.dirname(OUT[lang]), exist_ok=True)
        im.save(OUT[lang])
        os.remove(png)
        shutil.rmtree(profile, ignore_errors=True)
        print(f"[export] {lang}: {OUT[lang]} {im.size}")


def sheet() -> None:
    """多语 05 并排总览，方便一次性对比文案与配色。"""
    gap, pad = 40, 60
    thumbs = []
    for lang in ACTIVE:
        im = Image.open(OUT[lang])
        thumbs.append(im.resize((440, 956), Image.LANCZOS))
    w = pad * 2 + 440 * len(thumbs) + gap * (len(thumbs) - 1)
    h = pad * 2 + 956
    canvas = Image.new("RGB", (w, h), (243, 239, 250))
    x = pad
    for t in thumbs:
        canvas.paste(t, (x, pad))
        x += t.width + gap
    dst = os.path.join(WORK, "_05-三语总览.png")
    canvas.save(dst)
    print(f"[sheet] {dst} {canvas.size}")


def main() -> None:
    global ACTIVE
    ap = argparse.ArgumentParser()
    ap.add_argument("--step", default="all",
                    choices=["prepare", "statusbar", "html", "export", "sheet", "all"])
    ap.add_argument("--lang", default="all",
                    help="只处理某一语（zh-Hans / en-US / zh-Hant），默认全部")
    a = ap.parse_args()
    if a.lang != "all":
        if a.lang not in LANGS:
            ap.error(f"未知语言 {a.lang}")
        ACTIVE = [a.lang]
    if a.step in ("prepare", "all"):
        prepare()
    if a.step in ("statusbar", "all"):
        statusbar()
    if a.step in ("html", "all"):
        build_html()
    if a.step in ("export", "all"):
        export()
    if a.step in ("sheet", "all"):
        sheet()


if __name__ == "__main__":
    sys.exit(main())
