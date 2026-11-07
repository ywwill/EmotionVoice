# -*- coding: utf-8 -*-
"""
iPad 真机截图 → 预览图界面素材（real/ 只读，产物写 raw/）
=========================================================
真机源：ios_previews_ipad/real/<locale>/  ← 只读，任何命令都不会覆盖
        zh-Hans 沿用 2026-11-06 的旧编号 01/02/03/05/06；
        en-US / zh-Hant 一律 01-studio / 02-voices / 03-command /
        04-player / 05-projects（见 map_for）
        （real/zh-Hans/04-generate.png 仅存档，v3 起不进成片）
产物：  ios_previews_ipad/raw/<locale>/{studio,voices,command,player,projects}.png

三条分支（互不混用）：
  zh-Hans → 简体真机 + 02 抹数量 / 03 换稿 / 05 换历史数据
  en-US   → localize_en()：残留中文 → 英文 + 同口径数据优化
  zh-Hant → localize_hant()：⚠️ 不能复用英文路径（会把整页写成英文）；
            界面本身已是繁体，只把用户内容里的简体稿换成繁体 + 同口径数据优化

简体路径做的三处优化（其余像素原样保留）：
  02 抹掉「全部分类 599」里的具体数量，并把下拉箭头左移补回（全组禁写能力数量）
  03 换掉与 01 逐字相同的左栏 895 字 AI 稿，改成另一篇**无情绪标签**的口播稿；
     右栏描述框填入真实语音指令（真机是空占位符），让「说出来就行」在画面里真的发生
  06 把 16 张一模一样的测试卡换成 16 条不同记录（Chrome 渲染覆盖层，字体走 PingFang SC）

⚠️ 03 与 01 是同一个创作页的两种侧栏状态，真机左栏本就相同；商店缩略图里两页
   几乎无法区分，所以 03 按「另一次创作」处理：01 彩色标签密布＝手动精调，
   03 纯文本 + 已填指令＝一句话搞定。右栏语言 chips / 描述预设 / 提示语保持真机原样。
⚠️ 06 只替换卡片数据，不动统计条 / chips / 分组头的结构；
   16 张卡大小之和约 6.9 MB，与真机顶栏「6.81 MB」自洽。
⚠️ 头像是**音色名末字的白色汉字**（真机「龙安灵心」→ 心），不是抽象图形；
   之前用 SVG 折线画头像，看起来像残缺符号，v3 已改为文字。
"""
import os, sys, subprocess
from PIL import Image, ImageDraw

BASE = os.path.dirname(os.path.abspath(__file__))
IPAD = os.path.join(BASE, "ios_previews_ipad")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PROFILE = os.path.join(IPAD, "_profile_real")
W, H = 2224, 1668

# real 文件名 -> raw 文件名（v3：去掉生成浮层，成片 5 张）
# zh-Hans 沿用 2026-11-06 那批真机图的原始编号（05-player / 06-projects）；
# 之后新增的语言用 1–5 连续编号，避免再出现「文件编号 ≠ 成片编号」的歧义。
MAP_ZH = [
    ("01-studio",   "studio"),
    ("02-voices",   "voices"),
    ("03-command",  "command"),
    ("05-player",   "player"),
    ("06-projects", "projects"),
]
MAP_NEW = [
    ("01-studio",   "studio"),
    ("02-voices",   "voices"),
    ("03-command",  "command"),
    ("04-player",   "player"),
    ("05-projects", "projects"),
]

def map_for(locale):
    return MAP_ZH if locale == "zh-Hans" else MAP_NEW

PAGE_BG = (245, 241, 254)      # #F5F1FE
WHITE = (255, 255, 255)
BAR_BG = (253, 253, 255)       # 底部工具条


# ---------------------------------------------------------------- 02 音色库
def fix_voices(im):
    """抹「599」并把下拉箭头左移到「全部分类」右侧。"""
    im = im.copy()
    d = ImageDraw.Draw(im)
    # 白色通栏胶囊：x 258–360 / y 248–302 覆盖「599」与原箭头
    d.rectangle((258, 248, 362, 302), fill=(255, 255, 255))
    # 新箭头（V 形，颜色取真机箭头灰紫）
    ink = (86, 82, 108)
    d.line((266, 267, 276, 277, 286, 267), fill=ink, width=4, joint="curve")
    return im


# ---------------------------------------------------------------- 03 语音指令
# 与 01 完全不同的另一篇稿子：纯文本、无彩色情绪标签，视觉纹理一眼可分。
CMD_LINES = [
    "大家好，欢迎收听今天的《城市漫游》。",
    "我们把脚步放慢，沿着河岸往北走。",
    "秋天的风里有桂花的味道，很淡，却一直在。",
    "路边有人在卖烤红薯，铁桶上冒着白气。",
    "转过第二个街角，是一家开了三十年的旧书店。",
    "木门推开会响，老板抬头笑了一下，又低头继续修书。",
    "他说，最上层那本诗集等了很久，才等到有人把它抽出来。",
    "我们在窗边坐了一会儿，光从叶子的缝里落下来。",
    "这座城市不急着告诉你什么，它只是把细节留在原地。",
    "如果你也路过这里，不妨停下来，听一听风。",
    "下一期，我们去看入夜以后的旧码头。",
    "记得带上耳机，也记得带上一点耐心。",
    "那么，我们下期再见。",
]
CMD_SENTENCE = "用温柔的女声，语速放慢，像讲睡前故事；结尾稍微上扬，带一点期待感。"
CMD_CHARS = sum(len(x) for x in CMD_LINES)              # 253
CMD_CREDIT = "%.2f" % (33.54 * CMD_CHARS / 895)         # 与真机 895 字 ≈ 33.54 同比例
CMD_COUNT = len(CMD_SENTENCE)                            # 33

CMD_CSS = """
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:2224px;height:1668px;overflow:hidden;background:transparent;
  font-family:-apple-system,'PingFang SC','Helvetica Neue',sans-serif}
.a{position:absolute}
/* 左栏：用与真机卡片同形的白色圆角矩形整块盖掉 895 字 AI 稿（含彩色情绪标签）。
   ⚠️ 不能只盖 x100–1375 的文字区：旧彩色句段胶囊的圆角边缘会露在两侧。 */
.cardwipe{position:absolute;left:65px;top:145px;width:1340px;height:1245px;
  background:#fff;border-radius:24px}
.sepline{position:absolute;left:110px;top:196px;width:1250px;height:1px;
  background:#F0EDF6}
.wipe{background:#fff}
.ln{position:absolute;left:110px;height:64px;display:flex;align-items:center;gap:5px}
.ln span{display:inline-block;font-size:29px;color:#232136;line-height:1.35;
  white-space:nowrap;border:1px solid #EDEAF4;background:#FCFBFE;
  border-radius:14px;padding:7px 16px}
.caret{display:inline-block;width:3px;height:34px;background:#7B3FE8;border-radius:2px}
.word{position:absolute;left:1250px;top:158px;width:125px;text-align:right;
  font-size:20px;color:#8A87A0}
/* 底部积分预估，按新稿字数换算 */
.credit{position:absolute;left:68px;top:1503px;font-size:26px;font-weight:600;
  color:#1F1D2B;font-variant-numeric:tabular-nums}
/* 右栏：描述框从空占位符变成已经写好的指令 */
.cmdbox{position:absolute;left:1532px;top:1075px;width:536px;height:208px;
  background:#EDE8FC;border-radius:26px}
.cmdtxt{position:absolute;left:1558px;top:1102px;width:490px;font-size:25px;
  line-height:1.75;color:#2A2740}
.cnt{position:absolute;left:1890px;top:1298px;width:188px;text-align:right;
  font-size:19px;color:#8A87A0;font-variant-numeric:tabular-nums}
"""

CMD_TPL = """<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<style>__CSS__</style></head><body>
<div class="a cardwipe"></div>
<div class="a sepline"></div>
<div class="a word">__CHARS__ 字</div>
__LINES__
<div class="a wipe" style="left:60px;top:1498px;width:210px;height:48px;background:#FDFDFF"></div>
<div class="a credit">≈ __CREDIT__</div>
<div class="a cmdbox"></div>
<div class="a cmdtxt">用温柔的女声，语速放慢，像讲睡前故事；<br>结尾稍微上扬，带一点期待感。</div>
<div class="a wipe" style="left:1890px;top:1292px;width:190px;height:42px"></div>
<div class="a cnt">__COUNT__ / 1,000</div>
</body></html>"""


def overlay_png(raw_dir, html, tag):
    """Chrome 透明背景截图 → RGBA 覆盖层（默认背景色必须全透明）。"""
    tmp = os.path.join(raw_dir, "_%s.html" % tag)
    out = os.path.join(raw_dir, "_%s.png" % tag)
    open(tmp, "w", encoding="utf-8").write(html)
    os.makedirs(PROFILE, exist_ok=True)
    subprocess.run([
        CHROME, "--headless=new", "--no-sandbox", "--disable-gpu",
        "--disable-dev-shm-usage", "--hide-scrollbars",
        "--force-device-scale-factor=1", "--window-size=%d,%d" % (W, H),
        "--virtual-time-budget=2500", "--user-data-dir=" + PROFILE,
        "--default-background-color=00000000",
        "--screenshot=" + out, "file://" + tmp,
    ], check=True, capture_output=True)
    os.remove(tmp)
    im = Image.open(out).convert("RGBA")
    os.remove(out)
    if im.size != (W, H):
        im = im.resize((W, H), Image.LANCZOS)
    return im


def fix_command(im, raw_dir):
    """左栏换稿 + 右栏填上真实语音指令，其余真机像素不动。"""
    import html as _html
    lines = "".join(
        '<div class="a ln" style="top:%dpx"><span>%s</span>%s</div>'
        % (215 + i * 90, _html.escape(t),
           '<i class="caret"></i>' if i == len(CMD_LINES) - 1 else "")
        for i, t in enumerate(CMD_LINES))
    page = (CMD_TPL.replace("__CSS__", CMD_CSS)
                   .replace("__CHARS__", str(CMD_CHARS))
                   .replace("__CREDIT__", CMD_CREDIT)
                   .replace("__COUNT__", str(CMD_COUNT))
                   .replace("__LINES__", lines))
    layer = overlay_png(raw_dir, page, "cmd")
    return Image.alpha_composite(im.convert("RGBA"), layer).convert("RGB")


# ---------------------------------------------------------------- 06 历史记录
# 16 条不同记录：标题 / 音色 / 时长 / 大小 / 时间 / 头像渐变
HIST = [
    ("清晨，当你被手机闹钟唤醒", "龙安灵心", "00:26", "425.6 KB", "19:53", "#3ED3D0,#12A6C2"),
    ("新品开箱 · 便携蓝牙音箱",   "龙安鲁风", "00:34", "578.2 KB", "19:48", "#7FE3C4,#17A98C"),
    ("睡前故事：小熊的月亮",     "璨竹月",   "01:12", "612.4 KB", "19:32", "#FF9EC4,#E05C8A"),
    ("播客片头 · 第三季",         "蓉芷荷",   "00:08", "142.4 KB", "18:56", "#B79AFF,#7A4BE0"),
    ("课程开场白（试听）",       "朗虹沫",   "00:17", "296.8 KB", "18:20", "#74B9FF,#3B74D9"),
    ("品牌宣传片旁白",           "风月瑶",   "00:48", "812.5 KB", "17:44", "#FFC46B,#E8802F"),
    ("会议纪要摘要朗读",         "潇煜月",   "01:36", "528.3 KB", "17:05", "#C4A6FF,#7B5BE0"),
    ("晚安，今天也辛苦了",       "彤旭弦",   "00:12", "208.3 KB", "16:38", "#FFD08A,#E08A2F"),
    ("短视频口播 · 第 12 期",    "芷晴曦",   "00:19", "336.7 KB", "15:52", "#F7A8C4,#D25C8C"),
    ("客服欢迎语（普通话）",     "嵐柏弦",   "00:07", "128.6 KB", "15:10", "#8FD3F4,#4A90D9"),
    ("有声书 · 第一章试读",       "莹松柳",   "03:18", "963.4 KB", "14:36", "#A8E6CF,#3AAE8C"),
    ("节日祝福 · 双十一版",       "筝瑶鹤",   "00:14", "248.9 KB", "13:58", "#FFC98A,#E0902F"),
    ("产品介绍 · 功能串讲",       "岚煜芙",   "01:05", "512.6 KB", "12:42", "#9AD5C0,#2E9E7E"),
    ("儿童绘本朗读",             "霓岫涟",   "00:52", "604.2 KB", "11:20", "#D6B4FF,#8A5BE0"),
    ("导航提示音测试",           "溪凌璇",   "00:06", "112.4 KB", "10:47", "#8AD8F0,#3A8FD0"),
    ("活动暖场旁白",             "澄桃晦",   "00:23", "398.6 KB", "09:12", "#FFB4A8,#DE6B52"),
]

PLAY_SVG = """<svg viewBox="0 0 24 24" width="24" height="24"><path d="M9 5.5 L18 12 L9 18.5 Z" fill="#7B3FE8"/></svg>"""

CARDS_CSS = """
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:2224px;height:960px;overflow:hidden;background:#F5F1FE;
  font-family:-apple-system,'PingFang SC','Helvetica Neue',sans-serif}
.grp{position:absolute;left:66px;top:10px;font-size:20px;font-weight:600;color:#6B6885;
  display:flex;align-items:center;gap:8px}
.grp b{font-weight:600;color:#8A87A0}
.card{position:absolute;width:680px;height:126px;background:#fff;border-radius:20px;
  box-shadow:0 2px 10px rgba(70,45,130,.045)}
.ava{position:absolute;left:24px;top:19px;width:86px;height:87px;border-radius:22px;
  display:grid;place-items:center}
/* 头像 = 音色名末字的白色汉字，与真机一致（不是图形符号） */
.ava-t{font-size:46px;font-weight:500;line-height:1;color:#fff;
  transform:translateY(-2px);letter-spacing:0}
.title{position:absolute;left:134px;top:26px;width:418px;font-size:23px;font-weight:600;
  color:#232136;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;line-height:1.3}
.time{position:absolute;right:96px;top:31px;font-size:19px;color:#8A87A0;
  font-variant-numeric:tabular-nums}
.chip{position:absolute;left:134px;top:68px;font-size:16px;color:#6B3FE0;
  background:#EDE4FF;border-radius:12px;padding:3px 12px;line-height:1.35}
.meta{position:absolute;left:262px;top:73px;font-size:16px;color:#8A87A0;
  letter-spacing:.2px;font-variant-numeric:tabular-nums}
.play{position:absolute;right:23px;top:32px;width:62px;height:62px;border-radius:50%;
  background:#EDE7FB;display:grid;place-items:center}
"""

CARDS_TPL = """<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<style>__CSS__</style></head><body>
<div class="grp">今天 <b>16 条</b></div>
__CARDS__
</body></html>"""

def render_cards(raw_dir, hist=HIST, css=CARDS_CSS, tpl=CARDS_TPL, tag="cards"):
    """渲染 2224×960 的卡片区覆盖层，返回 PIL 图。
    默认参数 = 简体路径（逐字节不变）；繁体传入自己的数据 / 字体 / 组头。"""
    xs = [66, 771, 1476]
    ys = [56, 204, 352, 500, 648, 796]      # 原图 y = 616/764/912/1060/1208/1356，减 560
    parts = []
    for i, (title, voice, dur, size, tm, grad) in enumerate(hist):
        r, c = divmod(i, 3)
        g1, g2 = grad.split(",")
        ch = voice[-1]                       # 真机头像：音色名末字
        parts.append(
            '<div class="card" style="left:%dpx;top:%dpx">'
            '<div class="ava" style="background:linear-gradient(145deg,%s,%s)">'
            '<span class="ava-t">%s</span></div>'
            '<div class="title">%s</div><div class="time">%s</div>'
            '<div class="chip">%s</div><div class="meta">%s · %s</div>'
            '<div class="play">%s</div></div>'
            % (xs[c], ys[r], g1, g2, ch, title, tm, voice, dur, size, PLAY_SVG))
    html = tpl.replace("__CSS__", css).replace("__CARDS__", "".join(parts))
    tmp = os.path.join(raw_dir, "_%s.html" % tag)
    out = os.path.join(raw_dir, "_%s.png" % tag)
    open(tmp, "w", encoding="utf-8").write(html)
    os.makedirs(PROFILE, exist_ok=True)
    subprocess.run([
        CHROME, "--headless=new", "--no-sandbox", "--disable-gpu",
        "--disable-dev-shm-usage", "--hide-scrollbars",
        "--force-device-scale-factor=1", "--window-size=2224,960",
        "--virtual-time-budget=2500", "--user-data-dir=" + PROFILE,
        "--screenshot=" + out, "file://" + tmp,
    ], check=True, capture_output=True)
    os.remove(tmp)
    im = Image.open(out).convert("RGB")
    os.remove(out)
    if im.size != (2224, 960):
        im = im.resize((2224, 960), Image.LANCZOS)
    return im


def fix_projects(im, raw_dir):
    im = im.copy()
    im.paste(render_cards(raw_dir), (0, 560))
    return im


# ================================================================ en-US 本地化
# 英文真机图大部分界面已经是英文，只需要处理 5 类残留 / 优化：
#   ① 全部 5 张状态栏的中文日期「11月7日周六」→ Sat Nov 7
#   ② 02 抹掉「All Categories 599」里的数量并把下拉箭头左移（全组禁写能力数量）
#   ③ 03 左栏换掉与 01 逐字相同的 4110 字 AI 稿 → 另一篇纯文本口播稿 + 重算字数/积分
#   ④ 04 顶部中文文件名与正文卡里的中文稿 → 英文（这是用户点名的「4」）；
#      正文改为整段自动折 3 行 + 两端对齐，左右铺满卡片（v4.1，见 EN_PLAYER_TEXT 注释）
#   ⑤ 05 十六张全是同一条中文标题的测试卡 → 16 条不同英文记录（用户点名的「5」）
# 做法：PIL 先用区域众数底色抹掉中文，再用 Chrome RGBA 覆盖层重绘目标文字，
#       图形（波形 / 滑块 / 头像色块 / 按钮 / 图标）全部保留真机像素。
EN_FONT = "-apple-system,'Helvetica Neue',Arial,sans-serif"
EN_DATE = "Sat Nov 7"

EN_CMD_LINES = [
    "Welcome back to City Walks.",
    "We're taking it slow today, following the river north.",
    "There's osmanthus in the autumn air, faint but steady.",
    "Someone's selling roasted sweet potatoes by the corner.",
    "Steam rises off the iron cart and drifts away.",
    "Round the second bend is a bookshop, thirty years old.",
    "The door creaks. The owner looks up and smiles.",
    "Then he goes back to repairing an old spine.",
    "He says the poetry book up top waited a long time.",
    "We sit by the window; light falls through the leaves.",
    "This city never hurries to explain itself.",
    "It just leaves the small details where they are.",
    "If you pass through, stop and listen to the wind.",
    "Next week: the old docks after dark.",
    "Bring headphones, and a little patience.",
    "See you then.",
]
EN_CMD_CHARS = sum(len(x) for x in EN_CMD_LINES)
# 真机 4110 characters ≈ 82.2 积分（字符数 / 100 * 2），同比例换算
EN_CMD_CREDIT = "%.1f" % (EN_CMD_CHARS * 82.2 / 4110)

# 真机文件名带「副本」，直译成 "- Copy" 会让商店图看起来像未整理的测试账号；
# ASO 上属于负面信号，成片用干净的自然文件名。
EN_PLAYER_TITLE = "A Morning with AI"
# ⚠️ 04 文稿卡必须左右铺满：英文比中文「字宽」窄得多，早期用 3 行手断短句，
#    每行只到 x≈1160，卡片右侧 900px 全空，商店缩略图里像没写完。
#    改为整段自然换行 + text-align-last:justify：浏览器排成 3 行，
#    每行精确撑到 x≈2087（文本区 100..2090），词距只微调几像素，不出现拉伸感。
#    文案长度 526 字符是量过的：正好 3 行且第 3 行也接近满宽（少 30 字符会
#    出现第 3 行短一大截，多 30 字符会折成第 4 行溢出卡片）。
EN_PLAYER_TEXT = (
    "Your phone wakes you at the best point in your sleep cycle, and the speaker "
    "starts your playlist before you are fully awake. By the time you reach the "
    "kitchen, the coffee is already brewing. Before you leave, navigation has "
    "quietly picked the fastest route using live traffic, and the calendar has "
    "moved your first meeting to a room that is easy to find. Behind these "
    "ordinary moments is AI — no longer a distant sci-fi idea, but a quiet, "
    "invisible helper that stays out of the way and makes the day feel a little "
    "less rushed."
)
EN_PLAYER_CHARS = len(EN_PLAYER_TEXT)
EN_PLAYER_SENT = sum(EN_PLAYER_TEXT.count(c) for c in ".!?")

# 16 条不同记录：标题 / 音色（02 真机里的英文名）/ 时长 / 大小 / 时间 / 头像渐变
EN_HIST = [
    ("Waking up to your phone alarm",   "Lynn",     "00:26", "425.6 KB", "19:53", "#3ED3D0,#12A6C2"),
    ("Unboxing: the portable speaker",  "Lucas",    "00:34", "578.2 KB", "19:48", "#7FE3C4,#17A98C"),
    ("Bedtime story: The Bear's Moon",  "Abigail",  "01:12", "612.4 KB", "19:32", "#FF9EC4,#E05C8A"),
    ("Podcast intro · Season 3",        "Ada",      "00:08", "142.4 KB", "18:56", "#B79AFF,#7A4BE0"),
    ("Course opening (preview)",        "Aaron",    "00:17", "296.8 KB", "18:20", "#74B9FF,#3B74D9"),
    ("Brand film voiceover",            "Abel",     "00:48", "812.5 KB", "17:44", "#FFC46B,#E8802F"),
    ("Meeting notes read-aloud",        "Abraham",  "01:36", "528.3 KB", "17:05", "#C4A6FF,#7B5BE0"),
    ("Good night, you did enough",      "Adela",    "00:12", "208.3 KB", "16:38", "#FFD08A,#E08A2F"),
    ("Short video script · Ep 12",      "Adelaide", "00:19", "336.7 KB", "15:52", "#F7A8C4,#D25C8C"),
    ("Customer greeting (Mandarin)",    "Adam",     "00:07", "128.6 KB", "15:10", "#8FD3F4,#4A90D9"),
    ("Audiobook · Chapter 1 sample",    "Adeline",  "03:18", "963.4 KB", "14:36", "#A8E6CF,#3AAE8C"),
    ("Holiday greeting · November",     "Adrian",   "00:14", "248.9 KB", "13:58", "#FFC98A,#E0902F"),
    ("Product walkthrough",             "Adriana",  "01:05", "512.6 KB", "12:42", "#9AD5C0,#2E9E7E"),
    ("Children's picture book",         "Agatha",   "00:52", "604.2 KB", "11:20", "#D6B4FF,#8A5BE0"),
    ("Navigation prompt test",          "Agnes",    "00:06", "112.4 KB", "10:47", "#8AD8F0,#3A8FD0"),
    ("Event opening narration",         "Lucas",    "00:23", "398.6 KB", "09:12", "#FFB4A8,#DE6B52"),
]

EN_CSS = """
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:2224px;height:1668px;overflow:hidden;background:transparent;
  font-family:-apple-system,'Helvetica Neue',Arial,sans-serif}
.a{position:absolute}
.dt{left:100px;top:5px;font-size:24px;font-weight:500;color:#1B1A20;letter-spacing:.2px}
/* 03 左栏：与真机卡片同形的白色圆角矩形整块覆盖（不能只盖文字区，
   否则旧彩色句段胶囊的圆角边缘会露在两侧）。 */
.cardwipe{left:65px;top:145px;width:1340px;height:1245px;background:#fff;border-radius:24px}
.sepline{left:110px;top:196px;width:1250px;height:1px;background:#F0EDF6}
.word{left:1180px;top:158px;width:190px;text-align:right;font-size:20px;color:#8A87A0}
.ln{left:110px;height:72px;display:flex;align-items:center}
.ln span{display:inline-block;font-size:25px;color:#232136;line-height:1.3;
  white-space:nowrap;border:1px solid #EDEAF4;background:#FCFBFE;
  border-radius:14px;padding:7px 15px}
.caret{display:inline-block;width:3px;height:32px;background:#7B3FE8;border-radius:2px;margin-left:6px}
.credit{left:68px;top:1503px;font-size:26px;font-weight:600;color:#1F1D2B;
  font-variant-numeric:tabular-nums}
/* 04 播放详情 */
.ptitle{left:860px;top:72px;width:510px;text-align:center;font-size:31px;
  font-weight:700;color:#1B1533}
.pmeta{left:100px;top:938px;width:420px;font-size:19px;color:#8A87A0}
/* 04 正文：整段自动折行 + 两端对齐（含末行），左右严格贴卡片内边距；
   字号 / 行高与真机中文稿一致，禁止再用 3 个 nowrap 手断短句。 */
.pbody{left:100px;top:992px;width:1990px;font-size:25px;line-height:1.62;
  color:#1B152F;letter-spacing:.1px;text-align:justify;text-align-last:justify}
/* 05 历史卡 */
.grp{left:66px;top:570px;font-size:20px;font-weight:600;color:#6B6885;
  display:flex;align-items:center;gap:8px}
.grp b{font-weight:600;color:#8A87A0}
.card{width:680px;height:126px;background:#fff;border-radius:20px;
  box-shadow:0 2px 10px rgba(70,45,130,.045)}
.ava{left:24px;top:19px;width:86px;height:87px;border-radius:22px;
  display:grid;place-items:center}
.ava-t{font-size:46px;font-weight:500;line-height:1;color:#fff;transform:translateY(-2px)}
.title{left:134px;top:26px;width:410px;font-size:22px;font-weight:600;
  color:#232136;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;line-height:1.3}
.time{right:96px;top:31px;font-size:19px;color:#8A87A0;font-variant-numeric:tabular-nums}
.chip{left:134px;top:68px;font-size:16px;color:#6B3FE0;background:#EDE4FF;
  border-radius:12px;padding:3px 12px;line-height:1.35}
.meta{left:246px;top:73px;font-size:16px;color:#8A87A0;letter-spacing:.2px;
  font-variant-numeric:tabular-nums}
.play{right:23px;top:32px;width:62px;height:62px;border-radius:50%;
  background:#EDE7FB;display:grid;place-items:center}
"""

EN_ARROW = ('<svg class="a" style="left:338px;top:266px" width="28" height="18" '
            'viewBox="0 0 28 18"><path d="M4 5 L14 14 L24 5" fill="none" '
            'stroke="#56526C" stroke-width="3.5" stroke-linecap="round" '
            'stroke-linejoin="round"/></svg>')


def _en_page(body):
    return ('<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">'
            '<style>%s</style></head><body>%s</body></html>'
            % (EN_CSS, body))


def en_wipes(name, im):
    """PIL 阶段：把中文 / 599 用所在区域的众数底色抹掉。"""
    im = im.copy()
    d = ImageDraw.Draw(im)
    # ① 状态栏中文日期（5 张同位置）。⚠️「11月7日周六」从 x≈97 起，
    #    时间「12:24」到 x≈73 止；wipe 必须从 90 开始，否则残留「11」。
    d.rectangle((90, 2, 258, 44), fill=PAGE_BG)
    if name == "voices":
        # ② 「All Categories 599 ⌄」→ 抹 599 与原箭头，稍后重画箭头
        d.rectangle((332, 250, 440, 306), fill=WHITE)
    elif name == "command":
        # ③ 底部积分数字（Estimated 保留）
        d.rectangle((60, 1498, 230, 1552), fill=BAR_BG)
    elif name == "player":
        # ④ 中文文件名 / 元信息 / 中文正文
        d.rectangle((860, 62, 1380, 124), fill=PAGE_BG)
        d.rectangle((80, 932, 520, 982), fill=WHITE)
        d.rectangle((80, 990, 2120, 1112), fill=WHITE)
    elif name == "projects":
        # ⑤ 卡片区整片回到页面底色，随后由覆盖层重画 16 张卡
        d.rectangle((0, 560, 2224, 1525), fill=PAGE_BG)
    return im


def en_body(name, raw_dir):
    import html as _html
    parts = ['<div class="a dt">%s</div>' % EN_DATE]
    if name == "voices":
        parts.append(EN_ARROW)
    elif name == "command":
        parts.append('<div class="a cardwipe"></div>'
                     '<div class="a sepline"></div>'
                     '<div class="a word">%d characters</div>' % EN_CMD_CHARS)
        for i, t in enumerate(EN_CMD_LINES):
            parts.append('<div class="a ln" style="top:%dpx"><span>%s</span>%s</div>'
                         % (214 + i * 74, _html.escape(t),
                            '<i class="caret"></i>' if i == len(EN_CMD_LINES) - 1 else ""))
        parts.append('<div class="a credit">≈ %s</div>' % EN_CMD_CREDIT)
    elif name == "player":
        parts.append('<div class="a ptitle">%s</div>' % _html.escape(EN_PLAYER_TITLE))
        parts.append('<div class="a pmeta">%d Chars · %d Sentences</div>'
                     % (EN_PLAYER_CHARS, EN_PLAYER_SENT))
        parts.append('<div class="a pbody">%s</div>' % _html.escape(EN_PLAYER_TEXT))
    elif name == "projects":
        parts.append('<div class="a grp">Yesterday <b>16 Records</b></div>')
        xs = [66, 771, 1476]
        ys = [616, 764, 912, 1060, 1208, 1356]
        for i, (title, voice, dur, size, tm, grad) in enumerate(EN_HIST):
            r, c = divmod(i, 3)
            g1, g2 = grad.split(",")
            ch = voice[-1].lower()          # 英文真机头像 = 音色名末字母小写（Lynn → n）
            parts.append(
                '<div class="a card" style="left:%dpx;top:%dpx">'
                '<div class="a ava" style="background:linear-gradient(145deg,%s,%s)">'
                '<span class="ava-t">%s</span></div>'
                '<div class="a title">%s</div><div class="a time">%s</div>'
                '<div class="a chip">%s</div><div class="a meta">%s · %s</div>'
                '<div class="a play">%s</div></div>'
                % (xs[c], ys[r], g1, g2, ch, _html.escape(title), tm,
                   voice, dur, size, PLAY_SVG))
    return _en_page("".join(parts))


def localize_en(raw_dir, out):
    """英文真机图 → 无中文残留的 raw 界面图。"""
    for name, im in out.items():
        base = en_wipes(name, im)
        layer = overlay_png(raw_dir, en_body(name, raw_dir), "en_" + name)
        out[name] = Image.alpha_composite(base.convert("RGBA"), layer).convert("RGB")
    return out


# ================================================================ zh-Hant 本地化
# 繁体真机图 1/2/3 的**界面**已是繁体（App 语言切到 zh-Hant），但用户内容不会被翻译：
#   4 历史记录的 16 张卡、5 播放详情的标题与正文仍是简体稿（用户点名要换成繁体）。
# ⚠️ 绝不能走 localize_en()：那套覆盖层会把整页写成英文（EN_DATE / EN_PLAYER_TEXT /
#    EN_HIST / 英文头像规则）。繁体必须独立一套数据、字体与 wipe 坐标。
# 用词按 App zh-HK.lproj（專案／匯出／檔案／取樣率／搜尋／預設／螢幕／軟體／即時／想像），
# 不做纯 s2t；界面已本地化的部分一律保留真机像素。
HANT_FONT = "-apple-system,'PingFang TC','PingFang HK','Helvetica Neue',sans-serif"

# 03 左栏：与 01 完全不同的另一篇稿（纯文本、无彩色标签），缩略图里一眼可分。
# 真机 01/03 都是 1399 字 AI 稿 + 4 色标签，底部 ≈ 50.38，按同比例换算积分。
HANT_CMD_LINES = [
    "大家好，歡迎收聽今天的《城市漫遊》。",
    "我們把腳步放慢，沿著河岸往北走。",
    "秋天的風裡有桂花的味道，很淡，卻一直在。",
    "路邊有人在賣烤紅薯，鐵桶上冒著白氣。",
    "轉過第二個街角，是一家開了三十年的舊書店。",
    "木門推開會響，老闆抬頭笑了一下，又低頭繼續修書。",
    "他說，最上層那本詩集等了很久，才等到有人把它抽出來。",
    "我們在窗邊坐了一會兒，光從葉子的縫裡落下來。",
    "這座城市不急著告訴你什麼，它只是把細節留在原地。",
    "如果你也路過這裡，不妨停下來，聽一聽風。",
    "下一期，我們去看入夜以後的舊碼頭。",
    "記得帶上耳機，也記得帶上一點耐心。",
    "那麼，我們下期再見。",
]
HANT_CMD_SENTENCE = "用溫柔的女聲，語速放慢，像講睡前故事；結尾稍微上揚，帶一點期待感。"
HANT_CMD_CHARS = sum(len(x) for x in HANT_CMD_LINES)          # 253
HANT_CMD_CREDIT = "%.2f" % (50.38 * HANT_CMD_CHARS / 1399)     # 真机 1399 字 ≈ 50.38
HANT_CMD_COUNT = len(HANT_CMD_SENTENCE)                        # 33

# 繁体 03 右栏描述框比简体高 13px（chips 文案长度不同），只覆盖 top/height，
# 其余样式沿用 CMD_CSS；字体必须 PingFang TC，否则繁体走简体字形。
HANT_CMD_CSS = CMD_CSS + """
html,body{font-family:%s}
.cmdbox{top:1062px;height:213px}
.cmdtxt{top:1082px}
.cnt{top:1288px}
""" % HANT_FONT

HANT_CMD_TPL = CMD_TPL.replace(
    "用温柔的女声，语速放慢，像讲睡前故事；<br>结尾稍微上扬，带一点期待感。",
    "用溫柔的女聲，語速放慢，像講睡前故事；<br>結尾稍微上揚，帶一點期待感。")


def fix_command_hant(im, raw_dir):
    """繁体 03：左栏换稿 + 右栏填真实指令（与 01 去重）。"""
    import html as _html
    lines = "".join(
        '<div class="a ln" style="top:%dpx"><span>%s</span>%s</div>'
        % (215 + i * 90, _html.escape(t),
           '<i class="caret"></i>' if i == len(HANT_CMD_LINES) - 1 else "")
        for i, t in enumerate(HANT_CMD_LINES))
    page = (HANT_CMD_TPL.replace("__CSS__", HANT_CMD_CSS)
                        .replace("__CHARS__", str(HANT_CMD_CHARS))
                        .replace("__CREDIT__", HANT_CMD_CREDIT)
                        .replace("__COUNT__", str(HANT_CMD_COUNT))
                        .replace("__LINES__", lines))
    layer = overlay_png(raw_dir, page, "cmd_hant")
    return Image.alpha_composite(im.convert("RGBA"), layer).convert("RGB")


def fix_voices_hant(im):
    """繁体 02：抹「全部分類 599」的数量，箭头左移到文字右侧。
    ⚠️「類」右端约 x257，wipe 从 260 起，不能沿用简体版的 258（会切掉繁体字边缘）。"""
    im = im.copy()
    d = ImageDraw.Draw(im)
    d.rectangle((260, 246, 364, 306), fill=WHITE)
    ink = (86, 82, 108)
    d.line((269, 274, 279, 282, 289, 274), fill=ink, width=4, joint="curve")
    return im


# 04 播放详情：标题 / 正文是简体用户内容，界面标签（時長／格式／積分／複製）保留真机繁体。
# 正文同英文 v4.1 口径：整段自然换行 + 两端对齐，两行都铺到卡片右边界，
# 不能像简体真机那样第二行右侧空 225px。字数由 Chrome 实测为 2 行后定稿。
HANT_PLAYER_TITLE = "清晨，當你被手機鬧鐘 副本"
HANT_PLAYER_TEXT = (
    "清晨，當你被手機鬧鐘喚醒，螢幕根據你的睡眠週期自動調整到最佳時間；洗漱時，"
    "智能音箱播放著你常聽的音樂；出門前，導航軟體已結合即時路況規劃好最快路線——"
    "這些看似平常的場景，背後都有人工智能的身影。AI 早已不是科幻電影中的遙遠想像，"
    "而是悄然融入日常生活的隱形助手。它不搶話，只在你需要的時候，把一天輕輕推往前。"
)
HANT_PLAYER_CHARS = len(HANT_PLAYER_TEXT)
HANT_PLAYER_SENT = 5

HANT_PLAYER_CSS = """
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:2224px;height:1668px;overflow:hidden;background:transparent;
  font-family:%s}
.a{position:absolute}
.ptitle{left:860px;top:68px;width:510px;text-align:center;font-size:31px;
  font-weight:700;color:#1B1533}
.pmeta{left:98px;top:940px;width:420px;font-size:19px;color:#8A87A0}
.pbody{left:98px;top:990px;width:1990px;font-size:25px;line-height:2.1;
  color:#1B152F;letter-spacing:.1px;text-align:justify;text-align-last:justify}
""" % HANT_FONT


def hant_player_page():
    import html as _html
    body = ('<div class="a ptitle">%s</div>' % _html.escape(HANT_PLAYER_TITLE) +
            '<div class="a pmeta">%d 字 · %d 句</div>' % (HANT_PLAYER_CHARS, HANT_PLAYER_SENT) +
            '<div class="a pbody">%s</div>' % _html.escape(HANT_PLAYER_TEXT))
    return ('<!DOCTYPE html><html lang="zh-Hant"><head><meta charset="utf-8">'
            '<style>%s</style></head><body>%s</body></html>'
            % (HANT_PLAYER_CSS, body))


def fix_player_hant(im, raw_dir):
    """繁体 04：抹简体标题 / 元信息 / 正文，重绘繁体并让正文左右铺满。"""
    base = im.copy()
    d = ImageDraw.Draw(base)
    d.rectangle((860, 62, 1380, 124), fill=PAGE_BG)     # 标题（页面浅紫底）
    d.rectangle((80, 932, 520, 982), fill=WHITE)        # 130 字 · 4 句（卡片白底）
    d.rectangle((80, 990, 2120, 1100), fill=WHITE)      # 正文两行
    layer = overlay_png(raw_dir, hant_player_page(), "player_hant")
    return Image.alpha_composite(base.convert("RGBA"), layer).convert("RGB")


# 05 历史记录：16 张一模一样的简体测试卡 → 16 条不同繁体记录。
# 头像规则与简体一致 = 音色名末字的白色汉字（龍安靈心 → 心），不是图形。
HANT_HIST = [
    ("清晨，當你被手機鬧鐘喚醒", "龍安靈心", "00:26", "425.6 KB", "19:53", "#3ED3D0,#12A6C2"),
    ("新品開箱 · 便攜藍牙音箱",   "龍安魯風", "00:34", "578.2 KB", "19:48", "#7FE3C4,#17A98C"),
    ("睡前故事：小熊的月亮",     "璨竹月",   "01:12", "612.4 KB", "19:32", "#FF9EC4,#E05C8A"),
    ("播客片頭 · 第三季",         "蓉芷荷",   "00:08", "142.4 KB", "18:56", "#B79AFF,#7A4BE0"),
    ("課程開場白（試聽）",       "朗虹沫",   "00:17", "296.8 KB", "18:20", "#74B9FF,#3B74D9"),
    ("品牌宣傳片旁白",           "風月瑤",   "00:48", "812.5 KB", "17:44", "#FFC46B,#E8802F"),
    ("會議紀要摘要朗讀",         "瀟煜月",   "01:36", "528.3 KB", "17:05", "#C4A6FF,#7B5BE0"),
    ("晚安，今天也辛苦了",       "彤旭弦",   "00:12", "208.3 KB", "16:38", "#FFD08A,#E08A2F"),
    ("短片口播 · 第 12 集",      "芷晴曦",   "00:19", "336.7 KB", "15:52", "#F7A8C4,#D25C8C"),
    ("客服歡迎語（普通話）",     "嵐柏弦",   "00:07", "128.6 KB", "15:10", "#8FD3F4,#4A90D9"),
    ("有聲書 · 第一章試讀",       "瑩松柳",   "03:18", "963.4 KB", "14:36", "#A8E6CF,#3AAE8C"),
    ("節日祝福 · 雙十一版",       "箏瑤鶴",   "00:14", "248.9 KB", "13:58", "#FFC98A,#E0902F"),
    ("產品介紹 · 功能串講",       "嵐煜芙",   "01:05", "512.6 KB", "12:42", "#9AD5C0,#2E9E7E"),
    ("兒童繪本朗讀",             "霓岫漣",   "00:52", "604.2 KB", "11:20", "#D6B4FF,#8A5BE0"),
    ("導航提示音測試",           "溪凌璇",   "00:06", "112.4 KB", "10:47", "#8AD8F0,#3A8FD0"),
    ("活動暖場旁白",             "澄桃晦",   "00:23", "398.6 KB", "09:12", "#FFB4A8,#DE6B52"),
]
HANT_CARDS_CSS = CARDS_CSS.replace("'PingFang SC'", "'PingFang TC','PingFang HK'")
HANT_CARDS_TPL = (CARDS_TPL.replace('<html lang="zh-CN">', '<html lang="zh-Hant">')
                           .replace('<div class="grp">今天 <b>16 条</b></div>',
                                    '<div class="grp">昨天 <b>16 筆</b></div>'))


def fix_projects_hant(im, raw_dir):
    im = im.copy()
    im.paste(render_cards(raw_dir, HANT_HIST, HANT_CARDS_CSS,
                          HANT_CARDS_TPL, "cards_hant"), (0, 560))
    return im


def localize_hant(raw_dir, src):
    """繁体真机图 → 无简体残留的 raw 界面图。
    ⚠️ 状态栏「11月7日 週六」本身就是繁体，保留真机像素，不要 wipe。"""
    return {
        "studio":   src["studio"],
        "voices":   fix_voices_hant(src["voices"]),
        "command":  fix_command_hant(src["command"], raw_dir),
        "player":   fix_player_hant(src["player"], raw_dir),
        "projects": fix_projects_hant(src["projects"], raw_dir),
    }


# ---------------------------------------------------------------- 主流程
def prepare(locale="zh-Hans"):
    real = os.path.join(IPAD, "real", locale)
    raw = os.path.join(IPAD, "raw", locale)
    os.makedirs(raw, exist_ok=True)
    mp = map_for(locale)
    missing = [s for s, _ in mp if not os.path.isfile(os.path.join(real, s + ".png"))]
    if missing:
        raise SystemExit("缺少真机截图：%s（放在 %s）" % (", ".join(missing), real))

    src = {dst: Image.open(os.path.join(real, s + ".png")).convert("RGB")
           for s, dst in mp}
    for k, im in src.items():
        if im.size != (W, H):
            src[k] = im.resize((W, H), Image.LANCZOS)

    if locale == "zh-Hans":
        out = {
            "studio":   src["studio"],
            "voices":   fix_voices(src["voices"]),
            "command":  fix_command(src["command"], raw),
            "player":   src["player"],
            "projects": fix_projects(src["projects"], raw),
        }
    elif locale == "en-US":
        # 英文真机图：界面已英文化，只做「数据优化 + 残留中文 → 英文」
        out = localize_en(raw, dict(src))
    elif locale == "zh-Hant":
        # ⚠️ 繁体真机图不能复用英文路径：那会把整页写成英文。
        # 界面本身已是繁体，只需处理用户内容里的简体稿与重复测试数据。
        out = localize_hant(raw, dict(src))
    else:
        raise SystemExit("未知 locale：" + locale)

    keep = {n + ".png" for n in out}
    for f in os.listdir(raw):
        if f.endswith(".png") and f not in keep:
            os.remove(os.path.join(raw, f))     # 清掉 v2 的 generate.png / v1 的 params.png
    for name, im in out.items():
        p = os.path.join(raw, name + ".png")
        im.save(p, "PNG", optimize=True)
        print("真机 ->", os.path.relpath(p, BASE), im.size)
    import shutil
    shutil.rmtree(PROFILE, ignore_errors=True)
    return out


if __name__ == "__main__":
    loc = sys.argv[1] if len(sys.argv) > 1 else "zh-Hans"
    print("=== prepare real:", loc, "===")
    prepare(loc)
