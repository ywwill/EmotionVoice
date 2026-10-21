# -*- coding: utf-8 -*-
"""
Emora 商店预览图生成器（v4 · 中英双语，各 6 张）
================================================
01 / 02 / 03 / 06  使用真实截图（raw/<lang>/1-4.png，2x Retina）
04 声音描述 / 05 语言选择  为设计页（无需截图，数据取自 Constants.swift 真实值）

目录：
  raw/zh, raw/en      → 源截图（1 工作台 / 2 音色库 / 3 生成过程 / 4 我的项目）
  html/zh, html/en    → 布局确认页面
  mac-2880x1800/zh, /en → 导出成品（2880×1800 PNG）

用法：
  python3 gen_previews.py             生成两个语言的 html
  python3 gen_previews.py --export    生成 html 并导出 PNG
"""
import os, sys, shutil, subprocess

BASE   = os.path.dirname(os.path.abspath(__file__))
RAW    = os.path.join(BASE, "raw")
HTML   = os.path.join(BASE, "html")
EXPORT = os.path.join(BASE, "mac-2880x1800")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

W, H = 2880, 1800
HEAD_H, BOTTOM_PAD = 430, 110

# ------------------------------------------------------------------ 真实数据（Constants.swift）
PRESETS_ZH = [("温柔女声", "温柔的女性声音，语速适中，音色柔和亲切"),
              ("活泼男声", "年轻活泼的男性声音，语速偏快，语调积极"),
              ("新闻播报", "标准播音风格，吐字清晰，字正腔圆"),
              ("有声书",   "知性沉稳的讲述风格，富有感染力"),
              ("广告配音", "充满激情和说服力的广告风格，节奏明快"),
              ("教学讲解", "耐心细致的教学讲解风格，逻辑清晰")]
PRESETS_EN = [("Gentle Female Voice", "A gentle female voice with a moderate speaking pace and a soft, warm tone"),
              ("Lively Male Voice", "A young, energetic male voice with a fast speaking pace and an upbeat tone"),
              ("News Broadcast",    "A standard broadcasting style with clear articulation and precise pronunciation"),
              ("Audiobook",         "An intelligent, composed narration style with an engaging and expressive delivery"),
              ("Commercial Narration", "A passionate and persuasive advertising style with a lively pace"),
              ("Tutorial Narration",   "A patient and detailed instructional style with clear, logical explanations")]
INSTR_ZH = "知性沉稳的讲述风格，富有感染力"
INSTR_EN = "An intelligent, composed narration style with an engaging and expressive delivery"

STR = {
 "zh": dict(sep=" — ", lang_attr='lang="zh-CN"',
            font="-apple-system,'PingFang SC','Helvetica Neue',sans-serif"),
 # 英文页：标点一律英文写法（无间隔号 · / 无破折号），字体走西文栈
 "en": dict(sep=": ", lang_attr='lang="en"',
            font="-apple-system,'Helvetica Neue','Helvetica',Arial,sans-serif"),
}

LANG_GROUPS_ZH = [
 ("中文方言", ["中文", "粤语", "重庆话", "四川话", "东北话", "河南话", "陕西话", "天津话", "山东话"]),
 ("英文",     ["英文"]),
 ("欧洲语言", ["法语", "德语", "俄语", "葡萄牙语", "西班牙语", "意大利语"]),
 ("亚洲语言", ["日语", "韩语", "泰语", "印尼语", "越南语", "马来西亚语", "菲律宾语"]),
 ("其他",     ["阿拉伯语"])]
# 英文页：弱化中文与方言，国际语种优先（组序即展示顺序）
LANG_GROUPS_EN = [
 ("International", ["English", "French", "German", "Spanish", "Italian", "Portuguese",
                    "Russian", "Arabic"]),
 ("Asian",         ["Japanese", "Korean", "Thai", "Indonesian", "Vietnamese", "Malay",
                    "Filipino"]),
 ("Chinese Dialects", ["Chinese", "Cantonese", "Chongqing Dialect", "Sichuan Dialect",
                       "Northeastern Chinese Dialect", "Henan Dialect", "Shaanxi Dialect",
                       "Tianjin Dialect", "Shandong Dialect"])]

IMG = lambda n: {"mode": "image", "src": n}
LANGS = {
 "zh": dict(
   hot_lang={"四川话", "粤语"}, hot_preset="有声书", presets=PRESETS_ZH,
   instruction=INSTR_ZH, groups=LANG_GROUPS_ZH, groups_label="选择语言与方言",
   pages=[
    dict(id="01", kicker="语音合成工作台", title="按句插情绪，文字就有了语气",
         sub="丰富的语气与拟声标签，插在哪一句，就只影响哪一句", **IMG("1.png")),
    dict(id="02", kicker="音色库", title="先听再选，再决定用哪个声音",
         sub="按语言、性别、年龄、场景筛选，常用的收进收藏夹", **IMG("2.png")),
    dict(id="03", kicker="生成过程", title="几秒出音，进度实时可见",
         sub="生成状态、已接收大小与速率全程透明", **IMG("3.png")),
    dict(id="04", kicker="语音指令", title="不会调参数？说出来就行",
         sub="用一句话描述想要的声音，或从 6 种预设起步", mode="design-instruction"),
    dict(id="05", kicker="语言与方言", title="中文、英文，还有粤语、四川话",
         sub="多种语言与方言，选好语言再描述想要的声音", mode="design-language"),
    dict(id="06", kicker="我的项目", title="生成记录自动留存",
         sub="随时回听、重新导出，波形与参数都在", **IMG("4.png")),
   ]),
 "en": dict(
   hot_lang={"English", "Spanish"}, hot_preset="Audiobook", presets=PRESETS_EN,
   instruction=INSTR_EN, groups=LANG_GROUPS_EN, groups_label="Choose a language or dialect",
   pages=[
    dict(id="01", kicker="Voice Studio", title="Give every line its own tone",
         sub="Tone and sound tags change only the sentence they sit in", **IMG("1.png")),
    dict(id="02", kicker="Voice Library", title="Hear it before you pick it",
         sub="Filter by language, gender, age and use case; keep favourites close",
         **IMG("2.png")),
    dict(id="03", kicker="Generation", title="Audio in seconds, progress in view",
         sub="Status, size and transfer rate stay visible throughout", **IMG("3.png")),
    dict(id="04", kicker="Voice Instruction", title="Say it instead of tuning it",
         sub="Describe the voice you want in one sentence, or start from a preset",
         mode="design-instruction"),
    dict(id="05", kicker="Languages", title="English, French, Japanese and more",
         sub="Pick a language or dialect, then describe the voice you want",
         mode="design-language"),
    dict(id="06", kicker="Projects", title="Every generation is kept",
         sub="Replay or re-export anytime, waveform and settings intact", **IMG("4.png")),
   ]),
}

# ------------------------------------------------------------------ 样式
CSS = """
*{margin:0;padding:0;box-sizing:border-box}
body{width:2880px;height:1800px;overflow:hidden;position:relative;
     font-family:__FONT__;
     background:radial-gradient(1500px 900px at 84% -8%,rgba(232,169,104,.11),transparent 62%),
                linear-gradient(155deg,#0B0C0F 0%,#101216 55%,#15171C 100%)}
.head{padding:104px 160px 0}
.kicker{font-size:30px;letter-spacing:10px;color:#E8A968;font-weight:600;margin-bottom:26px}
h1{font-size:96px;font-weight:800;color:#F5F5F7;letter-spacing:2px;line-height:1.15}
.sub{font-size:42px;color:#9A9DA6;margin-top:24px;letter-spacing:1px}
.stage{position:absolute;left:0;right:0;display:flex;align-items:center;justify-content:center}
.win{position:relative;overflow:hidden;border-radius:28px;
     border:1px solid rgba(255,255,255,.14);box-shadow:0 40px 120px rgba(0,0,0,.55)}
.win img{display:block;width:100%;height:100%}
.panel{background:#15181D;border:1px solid rgba(255,255,255,.09);border-radius:30px;padding:52px 56px}
.plabel{font-size:28px;color:#7E828B;letter-spacing:3px;margin-bottom:26px}
.chip{display:inline-flex;align-items:center;height:78px;padding:0 34px;border-radius:16px;
      background:#21252C;color:#C9CCD3;font-size:34px;font-weight:600;letter-spacing:1px}
.chip.on{background:rgba(232,169,104,.16);color:#E8A968;box-shadow:inset 0 0 0 2px rgba(232,169,104,.55)}
.chips{display:flex;flex-wrap:wrap;gap:18px}
.grp{margin-bottom:44px}
.gname{font-size:30px;color:#8A8D94;margin-bottom:20px;letter-spacing:2px}
"""

def wrap(p, body_html):
    head = ('<div class="head"><div class="kicker">%s</div><h1>%s</h1>'
            '<div class="sub">%s</div></div>' % (p["kicker"], p["title"], p["sub"]))
    css = CSS.replace("__FONT__", STR[cfg_lang]["font"])
    tpl = ('<!DOCTYPE html><html __LANGATTR__><head><meta charset="utf-8">'
           '<style>%s</style></head>'
           '<body>%s<div class="stage" style="top:%dpx">%s</div></body></html>')
    tpl = tpl.replace("__LANGATTR__", STR[cfg_lang]["lang_attr"])
    return tpl % (css, head, HEAD_H, body_html)

def page_image(p, img_rel, src_w, src_h):
    avail = H - HEAD_H - BOTTOM_PAD
    dw = min(2360, avail * src_w / src_h)
    dh = dw * src_h / src_w
    return wrap(p, '<div class="win" style="width:%.0fpx;height:%.0fpx">'
                   '<img src="%s"></div>' % (dw, dh, img_rel))

def page_instruction(p, cfg):
    chips = "".join('<span class="chip%s">%s</span>'
                    % (" on" if n == cfg["hot_preset"] else "", n)
                    for n, _ in cfg["presets"])
    sep = STR[cfg_lang]["sep"]
    lines = "".join('<div style="font-size:30px;color:#7E828B;line-height:1.9">%s%s%s</div>'
                    % (n, sep, t) for n, t in cfg["presets"])
    body = """<div style="width:2400px">
      <div class="panel" style="margin-bottom:36px">
        <div class="plabel">%s</div>
        <div style="font-size:56px;color:#F5F5F7;line-height:1.5;letter-spacing:1px">
          %s<span style="color:#E8A968">&#9614;</span></div>
      </div>
      <div class="panel">
        <div class="plabel">%s</div>
        <div class="chips">%s</div>
        <div style="margin-top:40px;padding-top:34px;border-top:1px solid rgba(255,255,255,.08)">
          %s
        </div>
      </div>
    </div>""" % (LABELS[cfg_lang]["instr_title"], cfg["instruction"],
                 LABELS[cfg_lang]["presets_title"], chips, lines)
    return wrap(p, body)

def page_language(p, cfg):
    grps = []
    for gname, items in cfg["groups"]:
        ch = "".join('<span class="chip%s">%s</span>'
                     % (" on" if x in cfg["hot_lang"] else "", x) for x in items)
        grps.append('<div class="grp"><div class="gname">%s</div>'
                    '<div class="chips">%s</div></div>' % (gname, ch))
    body = ('<div style="width:2400px"><div class="panel">'
            '<div class="plabel">%s</div>%s</div></div>'
            % (cfg["groups_label"], "".join(grps)))
    return wrap(p, body)

LABELS = {
 "zh": dict(instr_title="语音指令 · 用一句话描述", presets_title="或从这里起步 · 6 种预设"),
 "en": dict(instr_title="Voice Instruction: Describe it in one sentence",
            presets_title="Or start from a preset"),
}
cfg_lang = None

# ------------------------------------------------------------------ 主流程
def build(lang):
    cfg = LANGS[lang]
    global cfg_lang
    cfg_lang = lang
    outdir = os.path.join(HTML, lang)
    os.makedirs(outdir, exist_ok=True)
    import struct
    def png_size(path):
        with open(path, "rb") as f:
            return struct.unpack(">II", f.read(26)[16:24])
    for p in cfg["pages"]:
        if p["mode"] == "image":
            shutil.copy(os.path.join(RAW, lang, p["src"]), os.path.join(outdir, p["src"]))
            sw, sh = png_size(os.path.join(RAW, lang, p["src"]))
            html = page_image(p, p["src"], sw, sh)
        elif p["mode"] == "design-instruction":
            html = page_instruction(p, cfg)
        else:
            html = page_language(p, cfg)
        with open(os.path.join(outdir, p["id"] + ".html"), "w", encoding="utf-8") as f:
            f.write(html)
    with open(os.path.join(outdir, "index.html"), "w", encoding="utf-8") as f:
        f.write(index_html(lang, cfg))
    return outdir

def index_html(lang, cfg):
    items = []
    for p in cfg["pages"]:
        src = p.get("src") or "设计页"
        items.append('<a class="card" href="%s.html"><div class="num">%s · %s</div>'
                     '<div class="t">%s</div><div class="s">%s</div>'
                     '<div class="st ok">%s</div></a>'
                     % (p["id"], p["id"], src, p["title"], p["sub"],
                        "真实截图" if p["mode"] == "image" else "设计稿（无截图）"))
    tpl = """<!DOCTYPE html><html><head><meta charset="utf-8"><style>
body{background:#0B0C0F;color:#F5F5F7;font-family:-apple-system,'PingFang SC',sans-serif;padding:60px;margin:0}
h1{font-size:44px;margin-bottom:8px}
.note{color:#9A9DA6;font-size:24px;margin-bottom:40px;line-height:1.6}
.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:28px}
.card{display:block;background:#15171C;border:1px solid rgba(255,255,255,.09);border-radius:20px;
      padding:32px;text-decoration:none;color:inherit}
.card:hover{border-color:rgba(232,169,104,.5)}
.num{font-size:24px;color:#E8A968;font-weight:700;letter-spacing:2px;margin-bottom:14px}
.t{font-size:32px;font-weight:700;margin-bottom:10px}
.s{font-size:22px;color:#9A9DA6;line-height:1.5;margin-bottom:18px}
.st{font-size:20px}
.st.ok{color:#7FBF7F}
</style></head><body>
<h1>Emora 预览图 · __L__（v4 · 6 张）</h1>
<div class="note">01/02/03/06 使用真实截图（2x Retina）；04 声音描述、05 语言选择为设计页。<br>
04/05 的数据取自 Constants.swift 的真实预设与语言列表。</div>
<div class="grid">__ITEMS__</div></body></html>"""
    name = {"zh": "中文版", "en": "English"}[lang]
    return tpl.replace("__ITEMS__", "".join(items)).replace("__L__", name)

def export(lang, outdir):
    exp = os.path.join(EXPORT, lang)
    os.makedirs(exp, exist_ok=True)
    for p in LANGS[lang]["pages"]:
        hp  = os.path.join(outdir, p["id"] + ".html")
        png = os.path.join(exp, "%s-%s.png" % (p["id"], p["kicker"].replace(" ", "-")))
        cmd = [CHROME, "--headless=new", "--no-sandbox", "--disable-gpu",
               "--disable-dev-shm-usage", "--hide-scrollbars",
               "--force-device-scale-factor=1", "--window-size=%d,%d" % (W, H),
               "--virtual-time-budget=4000",
               "--user-data-dir=" + os.path.join(BASE, "_build", "profile"),
               "--screenshot=" + png, "file://" + hp]
        subprocess.run(cmd, check=True, capture_output=True)
        print("png  ->", png)

if __name__ == "__main__":
    targets = sys.argv[1].split(",") if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else ["zh", "en"]
    for lang in targets:
        outdir = build(lang)
        print("html ->", outdir)
        if "--export" in sys.argv:
            export(lang, outdir)
