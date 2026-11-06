# -*- coding: utf-8 -*-
"""
Emora iOS App Store 预览图生成器（v2.4 · 多本地化：zh-Hans / en-US / zh-Hant）
==================================================================
规格：1320 × 2868 px（iPhone 6.9" 竖版，Apple 接受的三档里最高一档；
      ASC 会自动降采样覆盖 6.5"/6.3"/6.1"；RGB、无 alpha 通道）

界面素材来源：
  UI/iOS/emotionvoice-ios-design.html   01/03/04 创作工作台与语音指令 Sheet
  UI/iOS/history-redesign.html         05 播放详情 / 06 项目默认列表
  ios_previews/real/zh-Hans/voices-1.jpg  02 音色库【真机截图】（2026-11-06 用户提供）
  ⚠️ en-US / zh-Hant 的 02 暂无对应真机截图，改用设计稿音色库界面 + 文本替换（样张）

界面文案本地化口径：
  en-US  → EN_DICT（优先取 en.lproj 的 Localizable / VoiceCatalog 译文）
  zh-Hant → HANT_DICT（解析 zh-HK.lproj 的两份 .strings 得到「简体原文=繁体译文」，
            再叠一层设计稿展示文案覆写），未命中的走 OpenCC s2t 逐字兜底。
            ⚠️ 不能用纯 s2t：App 繁体界面是「項目→專案」「導出→匯出」
               「文件→檔案」「採樣率→取樣率」「搜索→搜尋」，机械转字全都不对。

目录（每条路径按 locale 分目录）：
  ios_previews/real/<locale>/         真机原图（不可变源）
  ios_previews/raw/<locale>/          界面素材（设计稿提取 or 真机处理后）
  ios_previews/html/<locale>/         HTML 母版（先在此确认构图）
  ios-1320x2868/<locale>/             导出的 1320×2868 PNG

用法：
  python3 gen_ios_previews.py                     三套 locale 一起出 HTML + 界面
  python3 gen_ios_previews.py --export           额外导出 1320×2868 PNG
  python3 gen_ios_previews.py --locale en-US --export
  python3 gen_ios_previews.py --locale zh-Hant --export
  python3 gen_ios_previews.py --html-only --export  只重建 HTML（不重新提取界面）

⚠️ 其余 5 张仍是设计稿样张，提审前用真机截图同名覆盖 raw/<locale>/ 后
   跑 `python3 gen_ios_previews.py --html-only --export`（必须带 --html-only，
   否则 extract_all() 会重新从设计稿提取并覆盖掉新截图）。
   真机界面自带「全部分类 599」「共 599 个」，换图后需确认不出现具体能力数量。
   设计稿只用于构图评审，不能直接作为提审素材。
⚠️ 四个英文区（en-US / en-GB / en-AU / en-CA）名称与副标题共用、字幕刻意避开
   favorite/colour 等英美拼写差异词，因此这一套 en-US 图可直接复用到其余三区。
⚠️ App 若支持 iPadOS，还必须另出一组 iPad 13" 2064×2752 截图。
"""
import os, sys, subprocess, shutil, json

BASE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(BASE, "..", "..", ".."))
DESIGN = os.path.join(ROOT, "UI", "iOS", "emotionvoice-ios-design.html")
HISTORY = os.path.join(ROOT, "UI", "iOS", "history-redesign.html")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PROFILE = os.path.join(BASE, "ios_previews", "_profile")
W, H = 1320, 2868
LOCALES = ["zh-Hans", "en-US", "zh-Hant"]

# App 真实繁体界面文案（HANT_DICT 的唯一来源，避免自己造词）
HANT_LPROJ = os.path.join(ROOT, "EmotionVoice", "EmotionVoice", "zh-HK.lproj")

def paths(locale):
    return dict(
        raw=os.path.join(BASE, "ios_previews", "raw", locale),
        real=os.path.join(BASE, "ios_previews", "real", locale),
        html=os.path.join(BASE, "ios_previews", "html", locale),
        export=os.path.join(BASE, "ios-1320x2868", locale),
    )

# Constants.swift 的 nlLanguages —— 语音指令模块「展开全部」后的 24 个语言/方言选项。
# ⚠️ 它不等于产品「支持的语言总数」：界面底部明确写「仅支持中文和英文输入」，
#    且音色库另有方言维度。因此图上字幕一律不写具体数量、不用「支持 N 种」的措辞。
LANGS = ["中文", "英文", "粤语", "重庆话", "四川话", "东北话", "河南话", "陕西话",
         "天津话", "山东话", "法语", "德语", "日语", "韩语", "俄语", "葡萄牙语",
         "泰语", "印尼语", "越南语", "西班牙语", "意大利语", "马来西亚语",
         "菲律宾语", "阿拉伯语"]
# 英文 chip 用短名，避免 24 个把 Sheet 撑出屏幕（方言用通名，不写 "Dialect" 后缀）
LANGS_EN = ["Chinese", "English", "Cantonese", "Chongqing", "Sichuan", "Dongbei",
            "Henan", "Shaanxi", "Tianjin", "Shandong", "French", "German",
            "Japanese", "Korean", "Russian", "Portuguese", "Thai", "Indonesian",
            "Vietnamese", "Spanish", "Italian", "Malay", "Filipino", "Arabic"]
# 繁体 chip：与 LANGS 一一对应，按台港用词（陝西／義大利／馬來西亞…），不用 s2t 硬转
LANGS_HANT = ["中文", "英文", "粵語", "重慶話", "四川話", "東北話", "河南話", "陝西話",
              "天津話", "山東話", "法語", "德語", "日語", "韓語", "俄語", "葡萄牙語",
              "泰語", "印尼語", "越南語", "西班牙語", "義大利語", "馬來西亞語",
              "菲律賓語", "阿拉伯語"]

def langs_for(locale):
    return {"zh-Hans": LANGS, "zh-Hant": LANGS_HANT}.get(locale, LANGS_EN)

# ---------------------------------------------------------------- 02 真机界面
# 用户提供的真机截图（885×1920）里，语种只出现在搜索框占位文字
# 「搜索音色名 / 特质 / 场景 / 语种」，并没有独立的语种 chips 筛选行。
# 因此 zh-Hans 的 02 不再做任何构图增强：直接用真机界面。
HIDE_VOICE_COUNT = True   # 延续「字幕/图上不写具体音色数量」口径，抹掉「全部分类 599」的 599
ADD_ISLAND = True         # 真机截图未带灵动岛；补一枚与其余 5 张一致
ISLAND_BOX = (414, 34, 762, 134)   # 1179×2556 界面素材上的坐标（半径 50 圆角）
COLOR_ISLAND = (10, 7, 20)
COLOR_PILL = (255, 255, 255)

# ---------------------------------------------------------------- 6 张分镜结构
# doc="design"  → screen / index 指定 emotionvoice-ios-design.html 的分区与第几台手机
# doc="history" → figure 指定 history-redesign.html 的 figure id
# doc="real"    → 真机截图，prepare_real() 从 ios_previews/real/<locale>/ 读取并处理
PAGES = [
    dict(id="01", src="studio-1", doc="design", screen="创作工作台", index=0, clean="studio"),
    dict(id="02", src="voices-1", doc="real", clean="none"),
    dict(id="03", src="studio-4", doc="design", screen="创作工作台", index=3, clean="languages"),
    dict(id="04", src="studio-3", doc="design", screen="创作工作台", index=2, clean="none"),
    dict(id="05", src="shot-favorite", doc="history", figure="shot-favorite", clean="player"),
    dict(id="06", src="shot-default", doc="history", figure="shot-default", clean="history"),
]

# en-US / zh-Hant 的 02 没有对应真机截图，退回设计稿音色库界面（同样无独立语种行），
# 再靠 VOICES_*_JS 补齐卡片、去掉数量，靠 EN_UI_JS / HANT_UI_JS 翻译界面文字。
PAGE_OVERRIDES = {
    "en-US": {"02": dict(doc="design", screen="音色库", index=0, clean="voices_en")},
    "zh-Hant": {"02": dict(doc="design", screen="音色库", index=0, clean="voices_hant")},
}

def pages_for(locale):
    out = []
    for p in PAGES:
        q = dict(p)
        q.update(PAGE_OVERRIDES.get(locale, {}).get(p["id"], {}))
        out.append(q)
    return out

# ---------------------------------------------------------------- 字幕层（按 locale）
# 英文字幕刻意避开 favorite/favourite、color/colour、voiceover/voice-over 等
# 英美拼写差异词，使同一套图能直接用于 en-US / en-GB / en-AU / en-CA。
# H1 两行、每行 ≤ 18 个西文字母（106px 字号 / 1080px 可用宽）；H2 一行 ≤ 48 字符。
COPY = {
    "zh-Hans": [
        ("按句加情绪，<br><em>文字才读得像人</em>", "情绪标签插在哪一句，就只影响哪一句"),
        ("海量音色，<br><em>先听再选</em>", "按名字、特质或语种搜索，常用的收进收藏"),
        ("不会调参数？<br><em>说出来就行</em>", "选好语言与语气，一句话描述声音"),
        ("想细调，<br><em>也随时能细调</em>", "语速、音量、MP3 / WAV、6 档采样率，都在一屏"),
        ("回听、倍速、导出，<br><em>都在一屏</em>", "波形拖定位，倍速、格式、音色一眼看全"),
        ("生成过的，<br><em>都给你留着</em>", "按日期分组、收藏与搜索，随时回听和导出"),
    ],
    "en-US": [
        ("Give every line<br><em>its own tone</em>", "Tone tags change only the sentence they sit in"),
        ("Hear it before<br><em>you pick it</em>", "Find a voice by name, trait or language"),
        ("Don't tune it.<br><em>Just say it.</em>", "Pick a language and tone, then describe it"),
        ("Fine-tune every<br><em>little detail</em>", "Speed, volume, MP3 / WAV and 6 sample rates"),
        ("Replay, speed up,<br><em>and export</em>", "Scrub the waveform, check speed, format and voice"),
        ("All your audio,<br><em>kept for you</em>", "Grouped by day, easy to search, replay and export"),
    ],
    # 繁中不是简繁转字：按台港用词重写（匯出／搜尋／取樣率／檔），与 App zh-HK 界面一致。
    # 「按句加情緒」的「才」在繁體同样写作「才」，不做「纔」的替換。
    "zh-Hant": [
        ("按句加情緒，<br><em>文字才讀得像人</em>", "情緒標籤插在哪一句，就只影響哪一句"),
        ("海量音色，<br><em>先聽再選</em>", "按名字、特質或語言搜尋，常用的收進收藏"),
        ("不會調參數？<br><em>說出來就行</em>", "選好語言與語氣，一句話描述聲音"),
        ("想細調，<br><em>也隨時能細調</em>", "語速、音量、MP3 / WAV、6 檔取樣率，全在一屏"),
        ("回聽、倍速、匯出，<br><em>都在一屏</em>", "波形拖定位，倍速、格式、音色一眼看全"),
        ("生成過的，<br><em>都給你留著</em>", "按日期分組、收藏與搜尋，隨時回聽和匯出"),
    ],
}

def copy_for(locale, i):
    h1, sub = COPY[locale][i]
    return h1, sub

# ---------------------------------------------------------------- 界面提取 CSS
DESIGN_CSS = """
<style id="asc-extract">
.topbar,.screen-head,figcaption{display:none!important}
.wrap{padding:0!important;margin:0!important;max-width:none!important}
.stage{display:block!important;gap:0!important}
figure.frame{margin:0!important}
.phone{box-shadow:none!important;border-radius:0!important;padding:0!important;
       width:393px!important;height:852px!important;background:transparent!important}
.viewport{width:393px!important;height:852px!important;border-radius:0!important}
/* Sheet 类界面：App 真实存在的 large detent，从状态栏下方开始，
   保留界面自带灵动岛与状态栏；去掉灰色遮罩，内容放大便于缩略图阅读 */
.sheet-scrim{display:none!important}
.sheet{top:52px!important;box-shadow:none!important}
.sheet-body{zoom:1.22}
/* 01 创作工作台：文本卡撑满 scroll 剩余空间，编辑内容按段均分间距 */
.asc-fill .scroll{display:flex;flex-direction:column}
.asc-fill .scroll>.card:last-child{flex:1;min-height:0;display:flex;flex-direction:column}
.asc-fill .scroll>.card:last-child>div:first-child{flex:none}
.asc-fill .scroll>.card:last-child>.hr{flex:none}
.asc-fill .scroll>.card:last-child .editor{flex:1;min-height:0;display:flex;
  flex-direction:column;justify-content:space-between}
.asc-fill .scroll>.card:last-child .editor .para{margin-bottom:0}
/* 徽章原本浮在胶囊左上（top:-14px），space-between 下会压到上一段；
   收进段落内部，并让拟声标签的 × 不遮住文字，保证缩略图可读 */
.asc-fill .scroll>.card:last-child .editor .badge{top:0}
.asc-fill .scroll>.card:last-child .editor .sfx .x{display:none}
</style>
"""

HISTORY_CSS = """
<style id="asc-hist">
html,body{padding:0!important;margin:0!important;background:#fff!important;
  overflow:hidden!important;width:393px!important;height:852px!important}
.sprite{position:absolute!important;width:0!important;height:0!important;overflow:hidden!important}
.frame{display:none!important}
.frame.asc-on{display:block!important;margin:0!important;padding:0!important;gap:0!important;
  position:absolute!important;top:0!important;left:0!important}
figcaption{display:none!important}
.phone-scaler{width:393px!important;height:852px!important;position:relative!important}
.phone{transform:none!important;box-shadow:none!important;border-radius:0!important;
  width:393px!important;height:852px!important;left:0!important;top:0!important}
</style>
"""

# --- 03 语音指令：按 Constants.nlLanguages 全量重建展开态（移除带数字的「展开全部」按钮）
LANGUAGES_JS_TMPL = r"""
(function(){
var ALL=__ALL__, ZOOM=__ZOOM__;
var root=document.querySelector('.screen.active');
var btn=[].slice.call(root.querySelectorAll('.chip')).filter(function(c){
  return c.textContent.indexOf('展开全部')>=0;
})[0];
if(!btn)return;
var row=btn.parentElement; btn.remove();
// 设计稿收起态只列了 5 个且漏掉「重庆话」，按 Constants.nlLanguages 全量重建展开态：
// 保留第一枚的选中样式，其余 23 个按源码顺序补上，避免重复/缺项。
var first=row.children[0];
row.innerHTML='';
// 设计稿收起态第一枚是「中文」且带选中样式；英文版沿用样式但换成英文文案
if(first){ first.textContent=ALL[0]; row.appendChild(first); }
ALL.slice(1).forEach(function(n){
  var c=document.createElement('span'); c.className='chip'; c.textContent=n;
  row.appendChild(c);
});
[].forEach.call(row.children,function(c){
  c.style.fontSize='12px'; c.style.padding='4px 9px';
});
var body=root.querySelector('.sheet-body'); if(body) body.style.zoom=ZOOM;
})();
"""

def languages_js(locale):
    return LANGUAGES_JS_TMPL \
        .replace("__ALL__", json.dumps(langs_for(locale), ensure_ascii=False)) \
        .replace("__ZOOM__", "0.98" if locale == "en-US" else "1.08")

# --- 01 创作工作台：文本卡撑满剩余空间 + 编辑内容扩成完整脚本
# ASO：首图必须一眼看出「同一段文字里，不同句子有不同情绪色块」。
# 因此保留 2 段无色默认语气作对照，4 种情绪色 + 2 个拟声错落分布。
# 英文版复用同一段中文结构，由 EN_UI_JS 把文案与字数标签一起翻成英文。
STUDIO_JS = r"""
(function(){
var root=document.querySelector('.screen.active');
var f=[].slice.call(root.querySelectorAll('figure.frame'))
        .filter(function(x){return x.style.display!=='none'})[0];
if(!f)return;
f.classList.add('asc-fill');
var card=f.querySelector('.scroll>.card:last-child');
var ed=card && card.querySelector('.editor');
if(!ed)return;

function badge(c,t){return '<span class="badge" style="--c:'+c+'">'+t+'<span class="x">×</span></span>';}
function cap(c,t){return '<span class="capsule" style="--c:'+c+'">'+t+'</span>';}
function sfx(c,t){return '<span class="sfx" style="--c:'+c+'">'+t+'<span class="x">×</span></span>';}
function para(s,pt){return '<div class="para" style="padding-top:'+pt+'px">'+s+'</div>';}
var PUR='#C07EE7', CYAN='#51C0D6', PINK='#E47FA8', BLUE='#6C8BE0', ORANGE='#F39E49';

ed.innerHTML=[
  para(badge(PUR,'😮 惊叹')+cap(PUR,'今天真是个好日子，我们终于见面了。')+sfx(ORANGE,'大笑'),24),
  para(cap(PUR,'我真的好开心啊，等了好久！'),6),
  para('接下来回到默认语气，不带任何情绪基调。',6),
  para(badge(CYAN,'😨 颤抖')+cap(CYAN,'可是我、我又有点紧张……'),24),
  para(badge(PINK,'🥰 温柔')+cap(PINK,'别怕，慢慢来，我在这儿等你。')+sfx(ORANGE,'轻叹'),24),
  para(badge(BLUE,'🤫 耳语')+cap(BLUE,'其实我早就想见你了。'),24),
  para('窗外的雨停了，屋子里安静下来。<span class="caret" style="margin-left:2px"></span>',6)
].join('');

// 字数按正文纯文本动态计算：徽章 / 拟声 / × 都是标记，不计入
var clone=ed.cloneNode(true);
[].forEach.call(clone.querySelectorAll('.badge,.sfx,.x,.caret'),function(x){x.remove();});
var n=Array.from(clone.innerText.replace(/\s/g,'')).length;
var lab=card.querySelector('.meta-line');
if(lab) lab.textContent=n+' 字';
})();
"""

# --- 02 en-US / zh-Hant：设计稿音色库界面（无独立语种行）→ 去数量 + 追加卡片填满下半屏
# 卡片结构 (头像字, 渐变, 音色名, 「特质 · 场景」, 年龄, 性别)
EXTRA_VOICE_CARDS_EN = [
    ("L", "linear-gradient(145deg,#B79AFF,#7A4BE0)", "Lydia", "Warm & sweet · Emotional narration", "27", "Female"),
    ("C", "linear-gradient(145deg,#FFC46B,#E8802F)", "Canton", "Native Cantonese · HK-style ads", "26", "Female"),
    ("S", "linear-gradient(145deg,#7FE3C4,#17A98C)", "Sichuan", "Playful dialect · Short video", "30", "Male"),
    ("B", "linear-gradient(145deg,#74B9FF,#3B74D9)", "Brian", "Clear British male · Narration", "35", "Male"),
]
# 繁体卡片用 App 里真实存在的音色（zh-HK VoiceCatalog 的繁体名）与特质
EXTRA_VOICE_CARDS_HANT = [
    ("荷", "linear-gradient(145deg,#B79AFF,#7A4BE0)", "蓉芷荷", "電台質感 · 長篇旁白", "30", "女"),
    ("月", "linear-gradient(145deg,#FFC46B,#E8802F)", "璨竹月", "平實質樸 · 有聲書", "28", "女"),
    ("瑤", "linear-gradient(145deg,#7FE3C4,#17A98C)", "風月瑤", "直爽利落 · 短影片配音", "27", "女"),
    ("沫", "linear-gradient(145deg,#74B9FF,#3B74D9)", "朗虹沫", "溫柔親和 · 品牌廣告", "32", "男"),
]

VOICES_JS_TMPL = r"""
(function(){
var CARDS=__CARDS__;
var root=document.querySelector('.screen.active');
var fr=[].slice.call(root.querySelectorAll('figure.frame'))
        .filter(function(x){return x.style.display!=='none'})[0];
if(fr){
  [].forEach.call(fr.querySelectorAll('.num'),function(n){
    if(n.textContent.trim()==='599') n.style.display='none';
  });
  [].forEach.call(fr.querySelectorAll('.res-cnt'),function(n){
    n.textContent=n.textContent.replace(/^共\s*599\s*[个個]\s*[·•]?\s*/,'');
  });
}
function mkCard(c){
  var btn='<span style="width:28px;height:28px;border-radius:6px;display:grid;place-items:center;border:.5px solid var(--line-2);color:var(--text-2)"><svg width="12" height="12" style="display:block"><use href="#i-play"/></svg></span>';
  var heart='<span style="width:28px;height:28px;border-radius:6px;display:grid;place-items:center;border:.5px solid var(--line-2);color:var(--text-2)"><svg width="13" height="13" style="display:block"><use href="#i-heart"/></svg></span>';
  var cta='<span style="width:26px;height:26px;border-radius:50%;display:grid;place-items:center;background:var(--grad-cta);color:var(--cta-fg)"><svg width="15" height="15" style="display:block"><use href="#i-arrow-rc"/></svg></span>';
  var meta='<span class="meta-line" style="font-size:10px;background:var(--surface-3);padding:1px 5px;border-radius:4px">'+c[4]+'</span>'+
           '<span class="meta-line" style="font-size:10px;background:var(--surface-3);padding:1px 5px;border-radius:4px">'+c[5]+'</span>';
  return '<div style="background:var(--surface);border:.5px solid var(--line);border-radius:12px;padding:12px">'+
    '<div style="display:flex;align-items:flex-start;gap:8px">'+
      '<div class="avatar" style="width:38px;height:38px;font-size:16px;background:'+c[1]+'">'+c[0]+'</div>'+
      '<div class="sp"></div>'+
      '<div class="rt" style="text-align:right;font-size:11px;color:var(--text-2);height:30px;line-height:1.35">'+c[3].split(' · ')[0]+'</div>'+
    '</div>'+
    '<div style="font-size:14.5px;font-weight:650;margin-top:9px">'+c[2]+'</div>'+
    '<div style="font-size:11px;color:var(--text-3);margin-top:2px;height:28px;line-height:1.35">'+c[3]+'</div>'+
    '<div style="display:flex;gap:6px;margin-top:7px">'+meta+'</div>'+
    '<div style="display:flex;align-items:center;gap:6px;margin-top:10px">'+btn+heart+'<span class="sp"></span>'+cta+'</div>'+
  '</div>';
}
var sc=root.querySelector('.scroll');
var grid=sc.querySelector('div[style*="grid-template-columns"]');
grid.insertAdjacentHTML('beforeend',CARDS.map(mkCard).join(''));
var last=sc.lastElementChild;
if(last && last.textContent.indexOf('上拉加载更多')>=0) last.remove();
})();
"""

def voices_js(locale):
    cards = EXTRA_VOICE_CARDS_HANT if locale == "zh-Hant" else EXTRA_VOICE_CARDS_EN
    return VOICES_JS_TMPL.replace("__CARDS__", json.dumps(cards, ensure_ascii=False))

# ---------------------------------------------------------------- 英文界面文本字典
# 键 = 设计稿里可见文本节点的 trim 值；值 = 英文界面文案。
# 译文优先取 App 自己的 en.lproj/Localizable.strings 与 VoiceCatalog.strings，
# 设计稿特有的展示文案按同一口径补齐。未命中的中文多为被 CSS 隐藏的说明文字，
# 不会出现在成品里。
EN_DICT = {
    # 导航 / 通用
    "创作": "Studio", "音色库": "Voices", "项目": "Projects", "历史记录": "History",
    "选择": "Select", "全部": "All", "收藏": "Saved", "今天": "Today", "昨天": "Yesterday",
    "更早": "Earlier", "完成": "Done", "更换": "Change", "删除": "Delete",
    "重命名": "Rename", "复制": "Copy", "复制音频": "Copy Audio",
    "从头播放": "Play from Start", "时长": "Duration", "格式": "Format",
    "积分": "Points", "大小": "Size", "音色": "Voice", "语音合成": "Speech",
    "文本输入": "Text Input", "预计": "Est.", "生成音频": "Create",
    "⭐ 旗舰": "⭐ Flagship", "文案 · 42 字": "Script · 42 characters",
    # 头像里的单字（音色名末字 → 英文名首字母，避免在英文界面里留汉字）
    "心": "Ly", "风": "Lu", "童": "Ki", "芷": "Ab", "欢": "Ad", "失": "!", "远": "Lu",
    # 01 工作台
    "龙安灵心": "Lynn", "龙安鲁风": "Lucas", "龙小童": "Kiddy",
    "温柔知性 · 日常对话 · 26 岁": "Warm & Caring · Everyday · 26",
    "😮 惊叹": "😮 Amazed", "😨 颤抖": "😨 Trembling", "🥰 温柔": "🥰 Tender",
    "🤫 耳语": "🤫 Whisper", "大笑": "Laughs", "轻叹": "Sighs",
    "今天真是个好日子，我们终于见面了。": "What a lovely day — we finally meet.",
    "我真的好开心啊，等了好久！": "I'm so happy! I've waited so long.",
    "接下来回到默认语气，不带任何情绪基调。": "Back to the default tone, no emotion tags.",
    "可是我、我又有点紧张……": "But I'm... I'm a little nervous.",
    "别怕，慢慢来，我在这儿等你。": "Don't worry. Take your time, I'm here.",
    "其实我早就想见你了。": "Truth is, I wanted to meet you long ago.",
    "窗外的雨停了，屋子里安静下来。": "The rain stopped; the room fell quiet.",
    # 02 音色库（设计稿样张）
    "搜索音色名 / 特质 / 场景 / 语种": "Search name, trait, scene or language",
    "全部分类": "All Categories",
    "共 599 个 · 旗舰优先，再按名称排序": "Flagship first, then by name",
    # VOICES_EN_JS 会先剥掉「共 599 个 · 」前缀，剩下半句也必须能命中
    "旗舰优先，再按名称排序": "Flagship first, then by name",
    "上拉加载更多": "Pull up to load more", "试听中": "Previewing",
    "温柔知性的女声，适合有声阅读": "A warm, gentle voice for audiobooks",
    "沉稳磁性的男声，适合新闻播报": "A deep, steady voice for news",
    "稚气可爱的童声": "A bright, playful child's voice",
    "低沉有力 · 中年成熟": "Deep & Strong · Mature",
    "活泼稚嫩 · 动画配音": "Playful · Animation",
    "标准美式发音 · 助手音色": "Standard US accent · Assistant",
    "女": "Female", "男": "Male",
    # 03 语音指令 Sheet
    "创作参数": "Studio Settings", "语音指令": "Voice Command", "语言": "Language",
    "中文": "Chinese",
    "描述预设": "Presets", "温柔女声": "Gentle Female", "活泼男声": "Lively Male",
    "新闻播报": "News Reader", "有声书": "Audiobook", "广告配音": "Commercial",
    "教学讲解": "Tutorial",
    "中文，年轻活泼的男性声音，语速偏快，语调积极": "A young, lively male voice, slightly fast and upbeat",
    "💡 详细描述 = 更好的效果": "💡 More detail, better results",
    "仅支持中文和英文输入": "Commands accept Chinese and English only",
    # 04 参数 Sheet
    "音频控制": "Audio Controls", "语速": "Speed", "音量": "Volume", "采样率": "Sample Rate",
    "语音通话": "Voice Calls", "AI 语音": "AI Voice", "网络语音": "VoIP",
    "CD 级音频": "CD Quality", "专业音频": "Studio",
    # 05 播放详情
    "今天真是个好日子…": "What a lovely day...",
    "今天真是个好日子，我们终于见面了，先来一段开场白……":
        "What a lovely day, we finally meet. Let's start with an intro...",
    "已加入收藏 · 可在「收藏」中快速找到": "Saved — find it quickly in Saved",
    # 06 项目列表
    "全部生成音频 · 按时间排列": "All audio · Newest first",
    "搜索名称、文案或音色": "Search name, script or voice",
    # 统计条的数字与单位是分开的文本节点，单位单独命中
    "条音频": "clips", "条本月": "this month",
    "2 条": "2 clips", "4 条": "4 clips",
    "今天真是个好日子，我们终于见面了…": "What a lovely day, we finally meet...",
    "各位听众晚上好，欢迎收听…": "Good evening, everyone. Welcome...",
    "生成中 62%": "Generating 62%",
    "别忘了给自己留一点时间。": "Don't forget to leave time for yourself.",
    "龙柏清芷": "Abigail", "龙安欢语": "Addie",
    "新品上线啦，快来抢先体验！": "New release is here — try it first!",
    "十月活动旁白（旧）": "October campaign (old)",
    "文件已丢失": "File missing", "无法播放": "Can't play",
    "10月28日 · 3 条": "Oct 28 · 3 clips",
    "深秋的雨落在窗台上…": "Late autumn rain on the windowsill...",
    "继续加载更早的记录…": "Load earlier recordings...",
    "龙安灵心 · 00:09 / 00:24": "Lynn · 00:09 / 00:24",
}

# 数字 + 单位这类组合无法用完整短语精确匹配，交给正则
EN_RULES = [
    (r"^(\d+)\s*字$", r"$1 characters"),
    (r"(\d+)\s*条音频", r"$1 clips"),
    (r"(\d+)\s*条本月", r"$1 this month"),
    (r"(\d+)\s*条", r"$1 clips"),
    (r"(\d+)\s*岁", r"$1 y/o"),
]

EN_UI_JS = r"""
<script>(function(){
var D=__DICT__, R=__RULES__;
function tr(raw){
  var t=raw.trim(); if(!t)return raw;
  if(Object.prototype.hasOwnProperty.call(D,t)) return raw.replace(t,D[t]);
  var s=raw;
  for(var i=0;i<R.length;i++){ s=s.replace(new RegExp(R[i][0],'g'),R[i][1]); }
  return s;
}
var w=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT,null,false);
var nodes=[],n;
while(n=w.nextNode()){
  var p=n.parentElement;
  if(!p||p.tagName==='SCRIPT'||p.tagName==='STYLE'||p.tagName==='NOSCRIPT')continue;
  nodes.push(n);
}
nodes.forEach(function(x){ var v=x.nodeValue, nv=tr(v); if(nv!==v)x.nodeValue=nv; });
// 01：英文正文比中文长，字数标签按替换后的正文重算
// （与 App 英文文案 "%d 字" = "%d characters" 一致）
var ed=document.querySelector('.asc-fill .editor');
if(ed){
  var c=ed.cloneNode(true);
  [].forEach.call(c.querySelectorAll('.badge,.sfx,.x,.caret'),function(x){x.remove();});
  var n2=Array.from((c.innerText||'').replace(/\s/g,'')).length;
  var lab=document.querySelector('.asc-fill .scroll>.card:last-child .meta-line');
  if(lab) lab.textContent=n2+' characters';
}
})();</script>
""" .replace("__DICT__", json.dumps(EN_DICT, ensure_ascii=False)) \
   .replace("__RULES__", json.dumps(EN_RULES, ensure_ascii=False))

# ---------------------------------------------------------------- 繁体界面文本字典
# 第一层：直接解析 App 自己的 zh-HK.lproj（Localizable + VoiceCatalog），
#   拿「简体原文 = 繁体译文」，保证与用户下载后看到的界面逐字一致：
#   设置→設定（不是設置）、项目→專案（不是項目）、导出→匯出（不是導出）、
#   文件→檔案、采样率→取樣率、搜索→搜尋、加载→載入、默认→預設。
# 第二层：设计稿特有的样张文案与假数据（strings 里没有），按同一口径补。
# 第三层：仍未命中的零星汉字走 OpenCC s2t 单字兜底（字表在下面生成）。
def _load_hk_strings():
    import re as _re
    out = {}
    for name in ("Localizable.strings", "VoiceCatalog.strings"):
        p = os.path.join(HANT_LPROJ, name)
        if not os.path.exists(p):
            continue
        for line in open(p, encoding="utf-8"):
            m = _re.match(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', line)
            if not m:
                continue
            k, v = m.group(1), m.group(2)
            # 跳过格式化占位符与转义串（含 %@ / \n 的 key 在截图里也用不上）
            if k == v or "%" in k or "\\" in k:
                continue
            if not (_re.search(r"[\u4e00-\u9fff]", k) and _re.search(r"[\u4e00-\u9fff]", v)):
                continue
            out.setdefault(k, v)
    return out

HANT_OVERRIDE = {
    # 02 音色库（设计稿样张）
    "全部分类": "全部分類",
    "共 599 个 · 旗舰优先，再按名称排序": "共 599 個 · 旗艦優先，再按名稱排序",
    "旗舰优先，再按名称排序": "旗艦優先，再按名稱排序",
    "上拉加载更多": "上拉載入更多",
    "试听中": "試聽中",
    "温柔知性的女声，适合有声阅读": "溫柔知性女聲，適合有聲書",
    "沉稳磁性的男声，适合新闻播报": "沉穩磁性的男聲，適合新聞播報",
    "稚气可爱的童声": "稚氣可愛的童聲",
    "低沉有力 · 中年成熟": "低沉有力 · 中年成熟",
    "活泼稚嫩 · 动画配音": "活潑稚嫩 · 動畫配音",
    "标准美式发音 · 助手音色": "標準美式發音 · 助手音色",
    "女": "女", "男": "男",
    # 01 工作台（STUDIO_JS 注入的正文与情绪徽章）
    "😮 惊叹": "😮 驚嘆", "😨 颤抖": "😨 顫抖", "🥰 温柔": "🥰 溫柔",
    "🤫 耳语": "🤫 耳語", "大笑": "大笑", "轻叹": "輕嘆",
    "今天真是个好日子，我们终于见面了。": "今天真是個好日子，我們終於見面了。",
    "我真的好开心啊，等了好久！": "我真的好開心啊，等了好久！",
    "接下来回到默认语气，不带任何情绪基调。": "接下來回到預設語氣，不帶任何情緒基調。",
    "别怕，慢慢来，我在这儿等你。": "別怕，慢慢來，我在這兒等你。",
    "其实我早就想见你了。": "其實我早就想見你了。",
    "窗外的雨停了，屋子里安静下来。": "窗外的雨停了，屋子裡安靜下來。",
    # 05 播放详情
    "今天真是个好日子…": "今天真是個好日子…",
    "今天真是个好日子，我们终于见面了，先来一段开场白……":
        "今天真是個好日子，我們終於見面了，先來一段開場白……",
    "已加入收藏 · 可在「收藏」中快速找到": "已加入收藏 · 可在「收藏」中快速找到",
    # 06 项目列表
    "全部生成音频 · 按时间排列": "全部生成音頻 · 按時間排列",
    "继续加载更早的记录…": "繼續載入更早的記錄…",
    "条音频": "條音頻", "条本月": "條本月",
    "2 条": "2 條", "4 条": "4 條",
    "今天真是个好日子，我们终于见面了…": "今天真是個好日子，我們終於見面了…",
    "各位听众晚上好，欢迎收听…": "各位聽眾晚上好，歡迎收聽…",
    "生成中 62%": "生成中 62%",
    "别忘了给自己留一点时间。": "別忘了給自己留一點時間。",
    "新品上线啦，快来抢先体验！": "新品上線啦，快來搶先體驗！",
    "十月活动旁白（旧）": "十月活動旁白（舊）",
    "文件已丢失": "檔案已遺失", "无法播放": "無法播放",
    "10月28日 · 3 条": "10月28日 · 3 條",
    "深秋的雨落在窗台上…": "深秋的雨落在窗台上…",
    "龙安灵心 · 00:09 / 00:24": "龍安靈心 · 00:09 / 00:24",
}

HANT_DICT = _load_hk_strings()
HANT_DICT.update(HANT_OVERRIDE)

# 单字兜底：OpenCC s2t 会给「爲 / 衆 / 裏 / 啓 / 臺」这些旧字形或非台港习惯写法，
# 按 App zh-HK 的实际用字覆盖（App 里「裡」1 次、「台」21 次、「啟」1 次）。
HANT_CHAR_FIX = {"为": "為", "众": "眾", "里": "裡", "台": "台", "启": "啟"}

def hant_char_map():
    """把所有会出现在界面上的汉字逐个 s2t，只保留「简≠繁」的映射。"""
    import re as _re
    try:
        from opencc import OpenCC
        cc = OpenCC("s2t")
    except Exception:
        print("⚠️ 未安装 opencc：繁体单字兜底不可用，只靠 zh-HK 词典（pip3 install opencc-python-reimplemented）")
        return {}
    chars = set()
    srcs = [DESIGN, HISTORY, os.path.abspath(__file__)]
    for p in srcs:
        if not os.path.exists(p):
            continue
        s = open(p, encoding="utf-8").read()
        s = _re.sub(r"<script.*?</script>", "", s, flags=_re.S)
        s = _re.sub(r"<style.*?</style>", "", s, flags=_re.S)
        chars |= set(_re.findall(r"[\u4e00-\u9fff]", s))
    out = {}
    for c in chars:
        f = cc.convert(c)
        if f != c:
            out[c] = HANT_CHAR_FIX.get(c, f)
    return out

HANT_UI_JS_TMPL = r"""
<script>(function(){
var D=__DICT__, K=__KEYS__, C=__CHARS__;
function tr(raw){
  var t=raw.trim();
  if(t && Object.prototype.hasOwnProperty.call(D,t)) return raw.replace(t,D[t]);
  var s=raw;
  // 词组优先（长 key 先替换），处理「设置→設定」这类字面转了也不对的情况
  for(var i=0;i<K.length;i++){
    var k=K[i];
    if(k.length>=2 && s.indexOf(k)>=0) s=s.split(k).join(D[k]);
  }
  var o='';
  for(var j=0;j<s.length;j++){ var ch=s[j]; o += (C[ch]||ch); }
  return o;
}
var w=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT,null,false);
var nodes=[],n;
while(n=w.nextNode()){
  var p=n.parentElement;
  if(!p||p.tagName==='SCRIPT'||p.tagName==='STYLE'||p.tagName==='NOSCRIPT')continue;
  nodes.push(n);
}
nodes.forEach(function(x){ var v=x.nodeValue, nv=tr(v); if(nv!==v)x.nodeValue=nv; });
// 01：正文替换后重算字数标签（单位繁体同样写「字」）
var ed=document.querySelector('.asc-fill .editor');
if(ed){
  var c=ed.cloneNode(true);
  [].forEach.call(c.querySelectorAll('.badge,.sfx,.x,.caret'),function(x){x.remove();});
  var n2=Array.from((c.innerText||'').replace(/\s/g,'')).length;
  var lab=document.querySelector('.asc-fill .scroll>.card:last-child .meta-line');
  if(lab) lab.textContent=n2+' 字';
}
})();</script>
"""

def hant_ui_js():
    keys = sorted([k for k in HANT_DICT if len(k) >= 2], key=len, reverse=True)
    return HANT_UI_JS_TMPL \
        .replace("__DICT__", json.dumps(HANT_DICT, ensure_ascii=False)) \
        .replace("__KEYS__", json.dumps(keys, ensure_ascii=False)) \
        .replace("__CHARS__", json.dumps(hant_char_map(), ensure_ascii=False))

def ui_js(locale):
    if locale == "en-US":
        return EN_UI_JS
    if locale == "zh-Hant":
        return hant_ui_js()
    return ""

CLEAN_JS_TMPL = {
    "studio": r"""
        [].forEach.call(document.querySelectorAll('.pill-btn'),function(el){
          if(el.textContent.indexOf('1,280')>=0) el.style.display='none';
        });
        [].forEach.call(document.querySelectorAll('div'),function(d){
          if(d.children.length===0 && d.textContent.indexOf('≈ 2.40')>=0 && d.parentElement)
            d.parentElement.style.visibility='hidden';
        });
        """ + STUDIO_JS,
}

def clean_js(locale, clean):
    if clean == "languages":
        return languages_js(locale)
    if clean in ("voices_en", "voices_hant"):
        return voices_js("en-US" if clean == "voices_en" else "zh-Hant")
    return CLEAN_JS_TMPL.get(clean, "")

def design_js(locale, screen, index, clean):
    return """<script>(function(){
var L=%s, I=%d;
var all=[].slice.call(document.querySelectorAll('.screen'));
all.forEach(function(s){s.classList.remove('active')});
var s=all.filter(function(x){return x.dataset.label===L})[0];
s.classList.add('active');
[].slice.call(s.querySelectorAll('figure.frame')).forEach(function(f,j){
  f.style.display=(j===I)?'block':'none';
});
%s
})();</script>""" % (json.dumps(screen, ensure_ascii=False), index,
                     clean_js(locale, clean))

PLAYER_JS = r"""
(function(){
var d=t.querySelector('.dock'); if(d) d.style.display='none';
[].forEach.call(t.querySelectorAll('div'),function(x){
  if(x.children.length!==0)return;
  var v=x.textContent.trim();
  if(v==='积分') x.textContent='大小';
  else if(v==='0.48') x.textContent='412 KB';
});
})();
"""

def history_js(figure, clean):
    return """<script>(function(){
document.body.classList.add('zoom-full');
var t=document.getElementById(%s);
document.body.appendChild(t);
[].forEach.call(document.body.children,function(el){
  if(el===t||el.tagName==='SVG'||el.tagName==='SCRIPT'||el.tagName==='STYLE')return;
  el.style.display='none';
});
t.classList.add('asc-on');
%s
window.scrollTo(0,0);
})();</script>""" % (json.dumps(figure, ensure_ascii=False),
                     PLAYER_JS if clean == "player" else "")

def shot(raw_dir, html, extra_css, extra_js, out):
    page = html.replace("</head>", extra_css + "</head>") \
               .replace("</body>", extra_js + "</body>")
    tmp = os.path.join(raw_dir, "_tmp.html")
    open(tmp, "w", encoding="utf-8").write(page)
    subprocess.run([
        CHROME, "--headless=new", "--no-sandbox", "--disable-gpu",
        "--disable-dev-shm-usage", "--hide-scrollbars",
        "--force-device-scale-factor=3", "--window-size=393,852",
        "--virtual-time-budget=3000", "--user-data-dir=" + PROFILE,
        "--screenshot=" + out, "file://" + tmp,
    ], check=True, capture_output=True)
    os.remove(tmp)

def prepare_real(src, out):
    """把真机截图处理成与其余 5 张界面素材同规格（1179×2556 = 393×852 @3x）。

    1) 「全部分类 599」的数字抹掉、下拉箭头左移贴紧文字，延续
       「字幕与图上都不写具体能力数量」的口径；收藏数是用户状态数据，保留。
    2) 真机截图未带灵动岛，补一枚与其余 5 张一致的黑色药丸，保证整组统一。
    其余界面内容（卡片、名称、浮动标签栏）100% 照真机原样，不做构图增强。
    """
    from PIL import Image, ImageDraw
    im = Image.open(src).convert("RGB")
    if HIDE_VOICE_COUNT:
        # 坐标基于用户提供的 885×1920 原图：
        # 「类」字结束 x≈225；数字 599 在 x≈240..292；箭头在 x≈302..330；y≈345..398
        arrow = im.crop((300, 343, 336, 400))
        d = ImageDraw.Draw(im)
        d.rectangle((234, 343, 336, 400), fill=COLOR_PILL)
        im.paste(arrow, (243, 343))
    target = (1179, 2556)
    if im.size != target:
        im = im.resize(target, Image.LANCZOS)
    if ADD_ISLAND:
        ImageDraw.Draw(im).rounded_rectangle(ISLAND_BOX, radius=50, fill=COLOR_ISLAND)
    im.save(out, "PNG", optimize=True)
    print("真机 ->", os.path.relpath(out, BASE))

def extract_all(locale):
    P = paths(locale)
    pages = pages_for(locale)
    os.makedirs(P["raw"], exist_ok=True)
    os.makedirs(PROFILE, exist_ok=True)
    keep = {p["src"] + ".png" for p in pages}
    for f in os.listdir(P["raw"]):
        if f.endswith(".png") and f not in keep:
            os.remove(os.path.join(P["raw"], f))
    design = open(DESIGN, encoding="utf-8").read()
    history = open(HISTORY, encoding="utf-8").read()
    for p in pages:
        out = os.path.join(P["raw"], p["src"] + ".png")
        if p["doc"] == "real":
            prepare_real(os.path.join(P["real"], p["src"] + ".jpg"), out)
            continue
        if p["doc"] == "history":
            css, js, src = HISTORY_CSS, history_js(p["figure"], p["clean"]), history
        else:
            css = DESIGN_CSS
            js = design_js(locale, p["screen"], p["index"], p["clean"])
            src = design
        if locale == "zh-Hant":
            css += TCH_FONT
        js += ui_js(locale)
        shot(P["raw"], src, css, js, out)
        print("界面 ->", os.path.relpath(out, BASE))
    shutil.rmtree(PROFILE, ignore_errors=True)

# 繁体界面必须用 PingFang TC 渲染：设计稿默认 --font 首选 PingFang SC，
# 繁体字会被简体字体的字形影响（「骨」「門」等部件写法不同），缩略图上一眼能看出来。
TCH_FONT = """
<style id="asc-tch">:root{--font:"PingFang TC","PingFang HK","Helvetica Neue",
  -apple-system,system-ui,sans-serif}</style>
"""

# ---------------------------------------------------------------- HTML 母版
CSS = """
*{margin:0;padding:0;box-sizing:border-box}
body{width:1320px;height:2868px;overflow:hidden;position:relative;
  font-family:-apple-system,'PingFang SC','Helvetica Neue',sans-serif;
  background:radial-gradient(1000px 780px at 88% 4%,rgba(138,91,255,.17),transparent 62%),
             radial-gradient(820px 700px at 2% 42%,rgba(255,95,162,.11),transparent 60%),
             radial-gradient(760px 640px at 96% 90%,rgba(46,217,191,.12),transparent 62%),
             linear-gradient(165deg,#F8F5FF 0%,#FFFFFF 52%,#F3EFFC 100%)}
.head{position:absolute;left:120px;right:120px;top:36px}
h1{font-size:106px;font-weight:800;line-height:1.22;
   letter-spacing:-2px;color:#1B1533}
h1 em{font-style:normal;background:linear-gradient(100deg,#5B2EDB,#CE2B72);
      -webkit-background-clip:text;background-clip:text;color:transparent}
.sub{margin-top:24px;font-size:42px;line-height:1.5;color:#5C5780;letter-spacing:.5px}
.stage{position:absolute;left:0;right:0;top:538px;display:flex;justify-content:center}
.device{position:relative;width:1033px;height:2240px;border-radius:112px;padding:13px;
  background:linear-gradient(150deg,#FFFFFF,#E9E3F8);
  box-shadow:0 60px 140px rgba(60,30,130,.20),0 8px 30px rgba(60,30,130,.10),
             inset 0 0 0 2px rgba(255,255,255,.92)}
.screen{width:100%;height:100%;border-radius:99px;overflow:hidden;
        position:relative;background:#F5F1FE}
.screen img{width:100%;height:100%;display:block;object-fit:cover}
.dots{position:absolute;left:0;right:0;bottom:40px;display:flex;
      justify-content:center;gap:16px}
.dots i{width:14px;height:14px;border-radius:999px;background:#D8CFEE;display:block}
.dots i.on{width:46px;background:linear-gradient(90deg,#5B2EDB,#CE2B72)}
"""

CSS_EN = CSS + """
/* 英文页走西文字体栈：PingFang 渲染拉丁字母偏宽，会让 H1 两行折成三行 */
body,h1,.sub{font-family:-apple-system,'Helvetica Neue',Helvetica,Arial,sans-serif!important}
.sub{letter-spacing:0!important}
"""

CSS_HANT = CSS + """
/* 繁体页改用 PingFang TC：H1/H2 里「讀」「覺」「匯」等字不能用简体字形渲染 */
body,h1,.sub{font-family:-apple-system,'PingFang TC','PingFang HK','Helvetica Neue',
  sans-serif!important}
"""

LANG_ATTR = {"zh-Hans": "zh-CN", "en-US": "en", "zh-Hant": "zh-Hant"}
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
    h1, sub = copy_for(locale, idx)
    dots = "".join('<i class="%s"></i>' % ("on" if j == idx else "") for j in range(total))
    return PAGE_TPL % dict(lang=LANG_ATTR[locale], css=CSS_BY_LOCALE[locale],
                           h1=h1, sub=sub, locale=locale, src=p["src"], dots=dots)

INDEX_TMPL = """<!DOCTYPE html><html lang="__LANG__"><head><meta charset="utf-8"><style>
body{background:#0E0C18;color:#F5F2FF;font-family:-apple-system,'PingFang SC',sans-serif;
     padding:64px;margin:0}
h1{font-size:44px;margin-bottom:10px}
.note{color:#ADA5CC;font-size:23px;line-height:1.7;margin-bottom:44px}
.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:30px}
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
    "zh-Hans": dict(
        lang="zh-CN",
        title="Emora · iOS 预览图中文版（6 张 · 1320×2868）",
        note="点击任一张查看 1:1 母版。<b>02 已换为真机截图</b>（音色库没有独立语种筛选行，语种只写在搜索框里）；其余 5 张仍是设计稿样张，提审前同名覆盖 raw/zh-Hans/ 后重跑 <code>--html-only --export</code>（不能只跑 --export）。<br>"
             "标题与副标题贴到画布最顶部，无品牌行与序号；字幕与图上都不写具体能力数量；整组统一深色标题 / 浅雾紫底 / 完整设备框。"),
    "en-US": dict(
        lang="en",
        title="Emora · iOS Screenshots · English (6 × 1320×2868)",
        note="Click any card for the 1:1 master. <b>English UI text is translated from the hi-fi design source &mdash; these are still comps, not device captures.</b> Before submission, replace <code>raw/en-US/</code> with real English device screenshots (especially 02) and re-run <code>--html-only --export</code>.<br>"
             "One English set covers en-US / en-GB / en-AU / en-CA: the copy deliberately avoids favourite/favorite, colour/color and voice-over spellings. No brand row, no sequence numbers, and no concrete capability counts anywhere."),
    "zh-Hant": dict(
        lang="zh-Hant",
        title="Emora · iOS 預覽圖繁體中文版（6 張 · 1320×2868）",
        note="點任一張看 1:1 母版。<b>介面文案直接取自 App 的 zh-HK.lproj</b>（設定／專案／匯出／檔案／取樣率／搜尋），不是機械簡繁轉字；字形與字幕另按台港用詞重寫。<br>"
             "⚠️ 02 音色庫<b>暫用設計稿樣張</b>（尚無繁體真機截圖，與 en-US 同樣處理），提審前請用繁體真機截圖同名覆蓋 <code>raw/zh-Hant/</code> 後重跑 <code>--locale zh-Hant --html-only --export</code>（不能只跑 --export）。"
             "整組不寫具體能力數量。"),
}

def build_html(locale):
    P = paths(locale)
    pages = pages_for(locale)
    os.makedirs(P["html"], exist_ok=True)
    for i, p in enumerate(pages):
        open(os.path.join(P["html"], p["id"] + ".html"), "w", encoding="utf-8").write(
            page_html(locale, p, i, len(pages)))
    items = []
    for i, p in enumerate(pages):
        h1, sub = copy_for(locale, i)
        items.append('<a class="card" href="%s.html"><div class="num">%s</div>'
                     '<img src="../../../ios-1320x2868/%s/%s.png">'
                     '<div class="t">%s</div><div class="s">%s</div></a>'
                     % (p["id"], p["id"], locale, p["id"] + "-" + p["src"],
                        h1.replace("<br>", " ").replace("<em>", "").replace("</em>", ""),
                        sub))
    idx_html = (INDEX_TMPL
                .replace("__LANG__", INDEX_META[locale]["lang"])
                .replace("__TITLE__", INDEX_META[locale]["title"])
                .replace("__NOTE__", INDEX_META[locale]["note"])
                .replace("__ITEMS__", "".join(items)))
    open(os.path.join(P["html"], "index.html"), "w", encoding="utf-8").write(idx_html)
    print("HTML ->", os.path.relpath(P["html"], BASE))

def export(locale):
    P = paths(locale)
    pages = pages_for(locale)
    os.makedirs(P["export"], exist_ok=True)
    os.makedirs(PROFILE, exist_ok=True)
    keep = {"%s-%s.png" % (p["id"], p["src"]) for p in pages}
    for f in os.listdir(P["export"]):
        if f.endswith(".png") and f not in keep:
            os.remove(os.path.join(P["export"], f))
    for p in pages:
        hp = os.path.join(P["html"], p["id"] + ".html")
        png = os.path.join(P["export"], "%s-%s.png" % (p["id"], p["src"]))
        subprocess.run([
            CHROME, "--headless=new", "--no-sandbox", "--disable-gpu",
            "--disable-dev-shm-usage", "--hide-scrollbars",
            "--force-device-scale-factor=1", "--window-size=%d,%d" % (W, H),
            "--virtual-time-budget=4000", "--user-data-dir=" + PROFILE,
            "--screenshot=" + png, "file://" + hp,
        ], check=True, capture_output=True)
        # 强制精确尺寸 + RGB（禁 alpha），防止 headless 有 1px 偏差
        from PIL import Image
        im = Image.open(png).convert("RGB")
        if im.size != (W, H):
            im = im.resize((W, H), Image.LANCZOS)
        im.save(png, "PNG", optimize=True)
        print("PNG  ->", os.path.relpath(png, BASE))
    shutil.rmtree(PROFILE, ignore_errors=True)

if __name__ == "__main__":
    args = sys.argv[1:]
    locales = LOCALES
    if "--locale" in args:
        i = args.index("--locale")
        if i + 1 < len(args) and args[i + 1] in LOCALES:
            locales = [args[i + 1]]
    for loc in locales:
        print("=== locale:", loc, "===")
        if "--html-only" not in args:
            extract_all(loc)
        build_html(loc)
        if "--export" in args:
            export(loc)
