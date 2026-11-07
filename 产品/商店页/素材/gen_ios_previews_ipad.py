# -*- coding: utf-8 -*-
"""
Emora iPad App Store 预览图生成器（v4 · 横屏 2752×2064 · 真机版 · 5 张 · 多本地化）
==================================================================
规格：2752 × 2064 px（iPad Pro 13" 横屏，ASC 的 iPad 13" 槽；RGB、无 alpha）

界面素材（v2 起为**用户提供的 iPad 真机截图**）：
  ios_previews_ipad/real/<locale>/  ← 真机原图，只读，任何命令都不会覆盖
  prepare_ipad_real.py              ← 真机优化（抹数量 / 换稿 / 换历史数据 / 本地化残留）
  ios_previews_ipad/raw/<locale>/   ← 优化后的界面图（生成器读这里）
  UI/iOS/ipad-landscape-design.html ← 自绘样张，仅 --force-redraw 时回退

版式（横版海报，居中）：
  H1 106px 顶部居中 → H2 42px → 设备 2117×1598 → 进度点底部
  设备比例 4:3，屏幕 2077×1558，界面图按 0.7546 缩放贴入

用法：
  python3 gen_ios_previews_ipad.py --export                   所有已有真机图的语言
  python3 gen_ios_previews_ipad.py --locale en-US --export    只出一语言
  python3 gen_ios_previews_ipad.py --html-only --export       只重建 HTML（不重跑真机优化）
  python3 gen_ios_previews_ipad.py --force-redraw --export    强制回到自绘样张

⚠️ 缺真机图的语言会被**跳过**（不回退自绘稿）：不同本地化必须构图一致，
   混进 6 屏自绘稿会破坏 ASC 同一尺寸槽内的视觉连续性。补齐 real/<locale>/ 后重跑即可。
⚠️ real 命名：zh-Hans 沿用 2026-11-06 那批的 01/02/03/05/06 原始编号；
   之后新增语言一律用 01–05 连续编号，由 map_for(locale) 分派。
⚠️ v3：用户确认「04 生成浮层不需要」，整套收敛为 5 张并重新连续编号。
   zh-Hans 的 real/04-generate.png 仍保留作素材存档，不进 MAP。
⚠️ 创作页的「输入框 / 音频参数 / 语音指令」在真机上是**同一个界面**：左栏固定编辑区，
   右栏在参数与语音指令间切换。01 与 03 是它的两种侧栏状态，不要再拆成三个独立界面；
   两页左栏必须是**不同的稿子**，否则缩略图里几乎像同一张图（v3.1 / v4 已处理）。
⚠️ en-US / zh-Hant 界面不是重写一遍 UI，而是在各自真机图上做「残留中文替换 +
   与简体同口径的数据优化」；简体路径逐字节保持不变。
⚠️ 两套覆盖层**不能互用**：en-US 走 localize_en()（写英文、状态栏改 Sat Nov 7），
   zh-Hant 走 localize_hant()（写繁体、状态栏保留「11月7日 週六」）。
   prepare() 按 locale 分派，别把繁体塞进英文分支。
"""
import os, sys, subprocess, shutil, json

BASE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(BASE, "..", "..", ".."))
DESIGN = os.path.join(ROOT, "UI", "iOS", "ipad-landscape-design.html")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PROFILE = os.path.join(BASE, "ios_previews_ipad", "_profile")
W, H = 2752, 2064
IW, IH = 1376, 1032          # 界面逻辑尺寸（pt）
LOCALES = ["zh-Hans", "en-US", "zh-Hant"]
LANG_ATTR = {"zh-Hans": "zh-CN", "en-US": "en", "zh-Hant": "zh-Hant"}

def paths(locale):
    return dict(
        raw=os.path.join(BASE, "ios_previews_ipad", "raw", locale),
        html=os.path.join(BASE, "ios_previews_ipad", "html", locale),
        export=os.path.join(BASE, "ios-2752x2064", locale),
    )

PAGES = [
    dict(id="01", label="创作",     name="studio"),     # 创作页 · 参数侧栏状态
    dict(id="02", label="音色库",   name="voices"),
    dict(id="03", label="语音指令", name="command"),    # 创作页 · 指令侧栏状态
    dict(id="04", label="播放",     name="player"),
    dict(id="05", label="项目",     name="projects"),
]

# v3 删掉「一键生成 / 进度看得见」：那张浮层信息密度最低，在缩略图里既不传达
# 差异化能力也不推进决策，移除后每张都有独立卖点。参数卖点仍由 01 画面承载。
# 其余与 iPhone 组保持一致：两个尺寸槽在商店里分区展示，文案统一最省心。
COPY = {
    "zh-Hans": [
        ("按句加情绪，<br><em>文字才读得像人</em>", "情绪标签插在哪一句，就只影响哪一句"),
        ("海量音色，<br><em>先听再选</em>", "按名字、特质或语种搜索，常用的收进收藏"),
        ("不会调参数？<br><em>说出来就行</em>", "选好语言与描述预设，一句话描述声音"),
        ("回听、倍速、导出，<br><em>都在一屏</em>", "波形拖定位，倍速、格式、音色一眼看全"),
        ("生成过的，<br><em>都给你留着</em>", "按日期分组、收藏与搜索，随时回听和导出"),
    ],
    # 英/繁 5 条对应 iPhone 组的 01/02/03/05/06（iPad 组没有独立的参数页字幕），
    # 逐字沿用，保证两个尺寸槽在 ASC 里文案统一；四英文区共用这一套。
    "en-US": [
        ("Give every line<br><em>its own tone</em>", "Tone tags change only the sentence they sit in"),
        ("Hear it before<br><em>you pick it</em>", "Find a voice by name, trait or language"),
        ("Don't tune it.<br><em>Just say it.</em>", "Pick a language and tone, then describe it"),
        ("Replay, speed up,<br><em>and export</em>", "Scrub the waveform, check speed, format and voice"),
        ("All your audio,<br><em>kept for you</em>", "Grouped by day, easy to search, replay and export"),
    ],
    # 繁中按台港用词重写（匯出／搜尋／回聽），不是简繁转字。
    "zh-Hant": [
        ("按句加情緒，<br><em>文字才讀得像人</em>", "情緒標籤插在哪一句，就只影響哪一句"),
        ("海量音色，<br><em>先聽再選</em>", "按名字、特質或語言搜尋，常用的收進收藏"),
        ("不會調參數？<br><em>說出來就行</em>", "選好語言與語氣，一句話描述聲音"),
        ("回聽、倍速、匯出，<br><em>都在一屏</em>", "波形拖定位，倍速、格式、音色一眼看全"),
        ("生成過的，<br><em>都給你留著</em>", "按日期分組、收藏與搜尋，隨時回聽和匯出"),
    ],
}

# ---------------------------------------------------------------- 界面提取
EXTRACT_CSS = """
<style id="asc-ipad">
.screen-head,.cap,.topbar,.stage>.frame{display:none!important}
html,body{margin:0!important;padding:0!important;background:#F5F1FE!important;
  width:%dpx!important;height:%dpx!important;overflow:hidden!important}
.stage{padding:0!important;margin:0!important;display:block!important;gap:0!important}
.tablet{margin:0!important;box-shadow:none!important;border-radius:0!important;
  width:%dpx!important;height:%dpx!important}
</style>
""" % (IW, IH, IW, IH)

def pick_js(label):
    return """<script>(function(){
var L=%s;
var all=[].slice.call(document.querySelectorAll('.screen'));
all.forEach(function(s){s.classList.remove('active')});
var s=all.filter(function(x){return x.dataset.label===L})[0];
if(!s)return;
s.classList.add('active');
})();</script>""" % json.dumps(label, ensure_ascii=False)

def shot(raw_dir, html, extra_css, extra_js, out):
    page = html.replace("</head>", extra_css + "</head>") \
               .replace("</body>", extra_js + "</body>")
    tmp = os.path.join(raw_dir, "_tmp.html")
    open(tmp, "w", encoding="utf-8").write(page)
    subprocess.run([
        CHROME, "--headless=new", "--no-sandbox", "--disable-gpu",
        "--disable-dev-shm-usage", "--hide-scrollbars",
        "--force-device-scale-factor=2", "--window-size=%d,%d" % (IW, IH),
        "--virtual-time-budget=3000", "--user-data-dir=" + PROFILE,
        "--screenshot=" + out, "file://" + tmp,
    ], check=True, capture_output=True)
    os.remove(tmp)

def extract_all(locale):
    P = paths(locale)
    os.makedirs(P["raw"], exist_ok=True)
    os.makedirs(PROFILE, exist_ok=True)
    keep = {p["name"] + ".png" for p in PAGES}
    for f in os.listdir(P["raw"]):
        if f.endswith(".png") and f not in keep:
            os.remove(os.path.join(P["raw"], f))
    design = open(DESIGN, encoding="utf-8").read()
    for p in PAGES:
        out = os.path.join(P["raw"], p["name"] + ".png")
        shot(P["raw"], design, EXTRACT_CSS, pick_js(p["label"]), out)
        print("界面 ->", os.path.relpath(out, BASE))
    shutil.rmtree(PROFILE, ignore_errors=True)

# ---------------------------------------------------------------- HTML 母版
CSS = """
*{margin:0;padding:0;box-sizing:border-box}
body{width:2752px;height:2064px;overflow:hidden;position:relative;
  font-family:-apple-system,'PingFang SC','Helvetica Neue',sans-serif;
  background:radial-gradient(1300px 900px at 82% 0%,rgba(138,91,255,.17),transparent 62%),
             radial-gradient(1100px 820px at 4% 46%,rgba(255,95,162,.11),transparent 60%),
             radial-gradient(1000px 780px at 92% 96%,rgba(46,217,191,.12),transparent 62%),
             linear-gradient(165deg,#F8F5FF 0%,#FFFFFF 52%,#F3EFFC 100%)}
.head{position:absolute;left:120px;right:120px;top:58px;text-align:center}
h1{font-size:106px;font-weight:800;line-height:1.22;
   letter-spacing:-2px;color:#1B1533}
h1 em{font-style:normal;background:linear-gradient(100deg,#5B2EDB,#CE2B72);
      -webkit-background-clip:text;background-clip:text;color:transparent}
.sub{margin-top:18px;font-size:42px;line-height:1.5;color:#5C5780;letter-spacing:.5px}
.stage{position:absolute;left:0;right:0;top:412px;display:flex;justify-content:center}
.device{position:relative;width:2117px;height:1598px;border-radius:118px;padding:20px;
  background:linear-gradient(150deg,#FFFFFF,#E9E3F8);
  box-shadow:0 70px 150px rgba(60,30,130,.20),0 10px 34px rgba(60,30,130,.10),
             inset 0 0 0 2px rgba(255,255,255,.92)}
.screen{width:100%;height:100%;border-radius:100px;overflow:hidden;
        position:relative;background:#F5F1FE}
/* 真机图内缩 3.5%：设备圆角会吃掉状态栏左侧的「19」，四周露出的
   #F5F1FE 与真机界面底色一致，看不出接缝 */
.screen img{width:100%;height:100%;display:block;object-fit:cover;
        transform:scale(.965);transform-origin:center center}
.dots{position:absolute;left:0;right:0;bottom:20px;display:flex;
      justify-content:center;gap:16px}
.dots i{width:14px;height:14px;border-radius:999px;background:#D8CFEE;display:block}
.dots i.on{width:46px;background:linear-gradient(90deg,#5B2EDB,#CE2B72)}
"""

# 西文字体栈：PingFang 渲染拉丁字母偏宽，会让英文 H1 两行折成三行。
CSS_EN = CSS + """
body,h1,.sub{font-family:-apple-system,'Helvetica Neue',Helvetica,Arial,sans-serif!important}
.sub{letter-spacing:0!important}
"""
# 繁体必须走 PingFang TC，否则「讀／覺／匯」会被简体字形带偏。
CSS_HANT = CSS + """
body,h1,.sub{font-family:-apple-system,'PingFang TC','PingFang HK','Helvetica Neue',sans-serif!important}
"""
CSS_BY_LOCALE = {"zh-Hans": CSS, "en-US": CSS_EN, "zh-Hant": CSS_HANT}

PAGE_TPL = """<!DOCTYPE html><html lang="%(lang)s"><head><meta charset="utf-8">
<style>%(css)s</style></head><body>
<div class="head">
  <h1>%(h1)s</h1>
  <div class="sub">%(sub)s</div>
</div>
<div class="stage"><div class="device">
  <div class="screen"><img src="../../raw/%(locale)s/%(src)s.png"></div>
</div></div>
<div class="dots">%(dots)s</div>
</body></html>"""

def page_html(locale, p, idx, total):
    h1, sub = COPY[locale][idx]
    dots = "".join('<i class="%s"></i>' % ("on" if j == idx else "") for j in range(total))
    return PAGE_TPL % dict(css=CSS_BY_LOCALE[locale], lang=LANG_ATTR[locale],
                           h1=h1, sub=sub, locale=locale,
                           src=p["name"], dots=dots)

INDEX_TMPL = """<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8"><style>
body{background:#0E0C18;color:#F5F2FF;font-family:-apple-system,'PingFang SC',sans-serif;
     padding:64px;margin:0}
h1{font-size:44px;margin-bottom:10px}
.note{color:#ADA5CC;font-size:23px;line-height:1.7;margin-bottom:44px}
.grid{display:grid;grid-template-columns:repeat(2,1fr);gap:30px}
.card{display:block;background:#1B1731;border:1px solid rgba(255,255,255,.09);
      border-radius:22px;padding:30px;text-decoration:none;color:inherit}
.card:hover{border-color:rgba(183,154,255,.6)}
.card img{width:100%;border-radius:14px;display:block;margin-bottom:20px}
.num{font-size:22px;color:#B79AFF;font-weight:700;letter-spacing:2px;margin-bottom:10px}
.t{font-size:30px;font-weight:700;line-height:1.4}
.s{font-size:20px;color:#ADA5CC;margin-top:10px}
code{color:#D8C9FF}
</style></head><body>
<h1>__TITLE__</h1>
<div class="note">__NOTE__</div>
<div class="grid">__ITEMS__</div></body></html>"""

INDEX_META = {
    "zh-Hans": (
        "Emora · iPad 预览图中文版（5 张 · 2752×2064 · 真机版）",
        "点击任一张查看 1:1 母版。<b>界面取自 iPad 真机截图</b>（<code>real/zh-Hans/</code> 只读）："
        "01/03 是同一个创作页的参数 / 语音指令两种侧栏状态。v3 移除了信息密度最低的「生成浮层」，"
        "收敛为 5 张连续编号。三处优化：02 抹掉「599」、03 换掉与 01 逐字相同的左栏稿并填入真实语音指令、"
        "05 把 16 张重复测试卡换成 16 条不同记录（头像为音色名末字）。"),
    "en-US": (
        "Emora · iPad App Store Previews · English (5 shots · 2752×2064)",
        "Click any card for the 1:1 master. <b>UI comes from real iPad screenshots</b> "
        "(<code>real/en-US/</code>, read-only). Five local fixes: status-bar date, "
        "removing the concrete voice count on 02, a different script on 03 so it no longer "
        "duplicates 01, translating the Chinese title/script on 04, and replacing 16 identical "
        "test rows on 05 with 16 distinct clips. No capability counts anywhere."),
    "zh-Hant": (
        "Emora · iPad 預覽圖香港繁體版（5 張 · 2752×2064 · 真機版）",
        "點擊任一張查看 1:1 母版。<b>介面取自 iPad 真機截圖</b>（<code>real/zh-Hant/</code> 只讀）。"
        "字幕按台港用詞重寫（匯出／搜尋／回聽），與 App <code>zh-HK.lproj</code> 一致。"),
}

def build_html(locale):
    P = paths(locale)
    os.makedirs(P["html"], exist_ok=True)
    keep_html = {p["id"] + ".html" for p in PAGES} | {"index.html"}
    for f in os.listdir(P["html"]):
        if f.endswith(".html") and f not in keep_html:
            os.remove(os.path.join(P["html"], f))   # v3 清掉旧的 06.html
    for i, p in enumerate(PAGES):
        open(os.path.join(P["html"], p["id"] + ".html"), "w", encoding="utf-8").write(
            page_html(locale, p, i, len(PAGES)))
    items = []
    for i, p in enumerate(PAGES):
        h1, sub = COPY[locale][i]
        items.append('<a class="card" href="%s.html"><div class="num">%s</div>'
                     '<img src="../../../ios-2752x2064/%s/%s-%s.png">'
                     '<div class="t">%s</div><div class="s">%s</div></a>'
                     % (p["id"], p["id"], locale, p["id"], p["name"],
                        h1.replace("<br>", " ").replace("<em>", "").replace("</em>", ""),
                        sub))
    title, note = INDEX_META[locale]
    open(os.path.join(P["html"], "index.html"), "w", encoding="utf-8").write(
        INDEX_TMPL.replace("__TITLE__", title)
                  .replace("__NOTE__", note)
                  .replace("__ITEMS__", "".join(items))
                  .replace('<html lang="zh-CN">', '<html lang="%s">' % LANG_ATTR[locale]))
    print("HTML ->", os.path.relpath(P["html"], BASE))

def export(locale):
    P = paths(locale)
    os.makedirs(P["export"], exist_ok=True)
    os.makedirs(PROFILE, exist_ok=True)
    keep = {"%s-%s.png" % (p["id"], p["name"]) for p in PAGES}
    for f in os.listdir(P["export"]):
        if f.endswith(".png") and f not in keep:
            os.remove(os.path.join(P["export"], f))
    for p in PAGES:
        hp = os.path.join(P["html"], p["id"] + ".html")
        png = os.path.join(P["export"], "%s-%s.png" % (p["id"], p["name"]))
        subprocess.run([
            CHROME, "--headless=new", "--no-sandbox", "--disable-gpu",
            "--disable-dev-shm-usage", "--hide-scrollbars",
            "--force-device-scale-factor=1", "--window-size=%d,%d" % (W, H),
            "--virtual-time-budget=4000", "--user-data-dir=" + PROFILE,
            "--screenshot=" + png, "file://" + hp,
        ], check=True, capture_output=True)
        from PIL import Image
        im = Image.open(png).convert("RGB")
        if im.size != (W, H):
            im = im.resize((W, H), Image.LANCZOS)
        im.save(png, "PNG", optimize=True)
        print("PNG  ->", os.path.relpath(png, BASE))
    shutil.rmtree(PROFILE, ignore_errors=True)

def has_real(locale):
    from prepare_ipad_real import map_for
    real = os.path.join(BASE, "ios_previews_ipad", "real", locale)
    return all(os.path.isfile(os.path.join(real, s + ".png")) for s, _ in map_for(locale))

if __name__ == "__main__":
    args = sys.argv[1:]
    locales = LOCALES
    if "--locale" in args:
        i = args.index("--locale")
        if i + 1 < len(args) and args[i + 1] in LOCALES:
            locales = [args[i + 1]]
    for loc in locales:
        print("=== locale:", loc, "===")
        use_real = has_real(loc) and "--force-redraw" not in args
        # 缺真机图时**跳过**而不是回退自绘样张：不同本地化必须构图一致，
        # 混进 6 屏自绘稿会破坏 ASC 同一尺寸槽内的视觉连续性。
        if not use_real and "--force-redraw" not in args and "--html-only" not in args:
            print("跳过：缺少 %s 真机截图（补齐 real/%s/ 后重跑）" % (loc, loc))
            continue
        if "--html-only" not in args:
            if use_real:
                from prepare_ipad_real import prepare
                prepare(loc)
            else:
                print("真机图不全或指定 --force-redraw，回退自绘样张")
                extract_all(loc)
        build_html(loc)
        if "--export" in args:
            export(loc)
