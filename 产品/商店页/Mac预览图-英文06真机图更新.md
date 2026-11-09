# macOS 英文 06「Projects」真机图更新（2026-11-09）

## 这次改了什么

用户提供当前版 App 的英文「My Projects / 历史记录」真机截图，把英文 06 从
**早期 UI** 同步到**当前真实 UI**，与简中 06 / 繁中 v3 的 06 对齐。

| | 旧成片 | 新成片 |
|---|---|---|
| 底图 | 早期 2x Retina 截图（`raw/en/4.png`，已随 `raw/` 清理丢失） | 用户新截图 `mac_en_real/06-projects.jpg`（只读） |
| 左侧记录 | 每条带橙色圆形头像 | **无头像**，10 条记录分 3 个日期组（2026.10.31 / 10.29 / 10.26） |
| 侧栏 | 旧版 | `Create / Text-to-Speech / Voice Library / My Projects / Points Center / Settings` |
| 参数条 | `00:24 / 8.34 / Ella` | `Duration 01:21 / Format WAV / Points 16.4 / Voice Lynn` |
| 详情 | 旧英文稿 | `979 Chars · 16 Sentences`，《Building Modern macOS Applications with SwiftUI: A Developer's Guide》 |
| 其它 | 旧状态 | `Remaining 01:20 / Play from Beginning`、右上 `Export`、底部 `Paused · 00:01` + 快捷键提示完整 |

标题、副标题**完全不变**：
`Projects / Every generation is kept / Replay or re-export anytime, waveform and settings intact`。

窗口 `.win` 从历史遗留的 `2104×1260` 统一成 **`2112×1260`**，与简中 / 繁中 06 一致。
英文各页 `.win` 本来就各不相同（2122 / 2027 / 2133 / 2104），8px 差异不影响构图；
成片仍是 `2880×1800 / RGB / 无 alpha`。

## ⚠️ 半行英文：按用户要求保留原样

新真机图的详情卡片底部有一行被文本容器裁成半行的英文
（`"SwiftUI allows developers to describe user interfaces using a declarative syntax, instead of manually"`，
win 坐标 y1152–1163、x984–1800）。

**用户明确要求「裁成半行的英文不用管」**，所以本通道：

- ❌ 不调用 `clean_card_bottom()`
- ❌ 不按列取色、不铺单色、不整块 `paste` 纯底色条带
- ❌ 不贴字、不改任何文案
- ✅ 整幅缩放后原样交付

三语 06 的半行字处理**互不相同**，别互相抄：

| 语言 | 源图 | 半行字 | 处理 |
|---|---|---|---|
| 简中 | `1920×1145` 纯窗口 | 无（最后一行完整） | 不清理 |
| 繁中 | `1920×1145` 纯窗口 | 有（win y965–980） | v3 已用整块 `paste` 纯底色条带清理 |
| 英文 | `1920×1143` 纯窗口 | 有（win y1152–1163） | **用户要求保留，不清理** |

## 入口（两个新脚本，主生成器零改动）

```bash
cd 产品/商店页/素材
python3 prepare_mac_en_real.py      # 真机源 → html/en/win-06.png + 4.png
python3 gen_mac_en06.py --export    # 重建 html/en/06.html 并导出 06-Projects.png
```

`gen_mac_en06.py` 会自动调用 prepare，平时只跑第二条即可。它复用
`gen_previews.py` 的 `CSS` / `page_image` / `export`，并设置 `cfg_lang="en"`
（西文字体栈 + `lang="en"`）；导出用 `only={"06"}`，
**英文 01–05、简中 6 张、繁中 6 张一张都不重渲**。

产物：

- `素材/mac_en_real/06-projects.jpg` —— 只读源图，`1920×1143`
- `素材/html/en/win-06.png` —— 新 HTML 引用，`2112×1260`
- `素材/html/en/4.png` —— 同一份，兼容主生成器历史 HTML 的 `<img src="4.png">`
- `素材/html/en/06.html` —— 布局页
- `素材/mac-2880x1800/en/06-Projects.png` —— 提审成片
- `素材/mac-2880x1800/_06英文前后对比.png` —— 辅助对比图（提审目录外）

## 禁令（踩坑点）

1. ⚠️ **别套繁体 A 类截图的 `(58,39)-(1862,1114)` BOX**。那 4 张是
   `1920×1191`「窗口 + 桌面画布」；这张是 `1920×1143` **纯窗口铺满整幅**，
   必须整幅缩放到 `2112×1260`。套 BOX 会裁掉交通灯、左栏与底部状态栏。
2. ⚠️ **源图高度是 1143**（英文状态栏更矮），比简中 / 繁中 06 的 1145 少 2px。
   整幅 resize 有约 0.2% 纵向形变，肉眼不可见；**别为了凑 1145 去拉伸或补边**，
   那会引入色差线。
3. ⚠️ **别清理半行英文**（见上节，用户明确要求）。
4. ⚠️ **不要改 `gen_previews.py`**，也不要 `python3 gen_previews.py --export`
   全量重跑：`raw/` 已被清理，`build("en")` 会因找不到 `raw/en/*.png` 报错，
   且会重渲中英 12 张（英文 01 刚定过 v4.5 版式）。
5. ⚠️ **不要往 `raw/` 塞源图**（历史上被清理过）。源图放 `mac_en_real/`，
   中间产物放 `html/en/`。
6. ⚠️ 窗口四角圆角/阴影由 `.win` 的 `border-radius:28px; overflow:hidden`
   再裁一次，源图角上那点浅棕色桌面像素不会露出，别手动擦角。

## 校验结果

- 英文 06 成片 `2880×1800 / RGB`，无 alpha。
- **零回归**：简中 6 张 + 英文 01–05 + 繁中 6 张共 **17 张** md5 与动手前基线
  完全一致；`gen_previews.py` mtime 保持 `2026-11-09 10:05`，本次逐字节未改。
- **幂等**：`gen_mac_en06.py --export` 连续 4 次，md5 均为
  `30279340abebe93c9c73eb35fdf1e077`。
- 目视复核：整片、窗口区放大均无露白、白块、双层字、色带、错位；
  侧栏、10 条记录、参数条、Export、底部状态栏完整。
- 三语 06 当前 md5：简中 `ed275bc4…` / 英文 `30279340…` / 繁中 `973add89…`。

## 已知局限

- 源图是 `1920px` JPG（非 2x Retina），放大到 2112px 后小字比早期
  `raw/en/4.png` 略软；与简中 / 繁中 06 的清晰度一致。
- 详情卡片底部那行半行英文按用户要求保留，是 App 真实滚动裁切状态。
- 02 真机 UI 自带「全部 599」这类具体数量，音色数变动时需换图；与本次无关。
