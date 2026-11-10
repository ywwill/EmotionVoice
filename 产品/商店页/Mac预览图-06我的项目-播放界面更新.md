# Mac 预览图 06「我的项目 / Projects」—— 换当前播放器界面

> 用户给了新的 macOS 窗口截图（先是中文 / 英文，晚些补了繁体），要求**在原有文件上直接替换 06**，01–05 不动。

## 1. 改了什么

| 文件 | 变化 |
| --- | --- |
| `素材/html/zh/06.html` | 只改 `.win` 高度 `1260px → 1255px`；新增 `html{background:#0B0C0F}` 兜底 |
| `素材/html/en/06.html` | 同上 |
| `素材/html/zh/win-06.png` | 重新生成（新截图，2112×1255） |
| `素材/html/en/win-06.png` | 同上 |
| `素材/mac-2880x1800/zh/06-我的项目.png` | **覆盖**（2880×1800 RGB） |
| `素材/mac-2880x1800/en/06-Projects.png` | **覆盖**（2880×1800 RGB） |
| `素材/html/zh-Hant/06.html` | 同上（`1260px → 1262px`） |
| `素材/html/zh-Hant/win-06.png` | 重新生成（2112×1262） |
| `素材/mac-2880x1800/zh-Hant/06-我的項目.png` | **覆盖**（2880×1800 RGB） |
| 其余 9 张（01–05 三语） | **一字节未动**（md5 已逐张比对） |

标题/副标题文案**保持不变**：`我的项目 / 生成记录自动留存 / 随时回听、重新导出，波形与参数都在`。
新窗口里列表与播放器同屏，这句话仍然成立，不动文案能把「只换界面」的风险降到最低。

### 为什么窗口高不是一个数

旧窗口框统一 2112×1260。三张新图比例各不相同，按图算高度才不会纵向压扁：

| 语言 | 源图 | 窗口框 | 相对 1260 |
| --- | --- | --- | --- |
| 简中 / 英文 | 1920×1141（1.6827） | 2112×**1255** | −5px |
| 繁体 | 1920×1147（1.6739） | 2112×**1262** | +2px |

宽度仍是 2112，与 01–05 的体量一致；几像素的高度差在 1800 的画布上看不出来。

## 2. 入口

```bash
cd 产品/商店页/素材
python3 gen_mac_06.py                  # 三语全跑：src → win → html → export
python3 gen_mac_06.py --lang zh-Hant   # 只做某一语（换图时最常用）
python3 gen_mac_06.py --step export   # 只重渲 06 两张
```

- `--step src`：把上传的两张 1920×1141 截图归档成 `mac-06-src/{zh,en}/06-src.png`
  （剪贴板目录会被清理，源图必须落在仓库里）。
- `--step win`：LANCZOS 预缩放到 2112×1255 存成 `html/<lang>/win-06.png`，
  浏览器里 1:1 贴图，比交给 CSS 缩放锐。
- `--step html`：正则改 `.win` 高度（幂等，已是目标值就不写盘）。
- `--step export`：Chrome headless 2880×1800 → 覆盖 `mac-2880x1800/<lang>/06-*`。

## 3. 两个坑（都写进脚本了）

1. **Chrome 必须 `--no-sandbox`**：本环境的进程沙箱不允许 Chrome 起自己的 sandbox，
   否则 `sandbox initialization failed` → `GPU process isn't usable` → SIGTRAP 直接死。
2. ⚠️ **headless 偶发「视口最后 21px 没画完」**：实测 4 次渲染里有 1 次在 y1779–1800
   刷出**纯白条**（(255,255,255)，差 241/255），这也是「同一条命令导出两次 md5 会变」的真凶。
   两道处理：
   - `html{background:#0B0C0F}` —— 没画到的区域露深色而不是白；
   - `export_step` 出图后检查底部 24px 最大亮度，>200 就重渲（最多 4 次）。
   之后连跑 3 次导出，md5 完全一致。
3. 残余抖动：加上兜底后仍有一条约 13/255 的色带差异（`html` 底色 vs 渐变末端，只出现在
   最底 21px、且从 x≈2033 起），肉眼不可见但会让 md5 变。出口处把**最底 24 行统一成上一行**，
   彻底稳定（这一带本来就是近纯色渐变，抹平看不出差别）。

## 4. 校验

```
zh/06-我的项目.png      2880×1800 RGB  ed275bc4… → 6eb18816f6e9239bbaa7f0c560807904
en/06-Projects.png      2880×1800 RGB  30279340… → c0e26b21c6c2b6b5f72ac0480f68ad18
zh-Hant/06-我的項目.png  2880×1800 RGB  973add89… → 4d6878e2ee5efdd3462b286d83d53266
```

- 每张各跑 3 次 `--step export`，md5 一致；
- 01–05 九张 md5 与改前逐张相同；
- 窗口四角、交通灯、1px 边框均在（`.win` 的 `border-radius:28px` 只削 8px 角落三角，不碰灯）。

## 5. 繁体补上了（11-10 晚）

简体、英文先在 16:55 换完；当晚补到繁体窗口截图（1920×1147，同一段「靜謐時光裡的療癒力量」），
`--lang zh-Hant` 一条命令补齐：

```bash
python3 gen_mac_06.py --lang zh-Hant --step src   # 归档到 mac-06-src/zh-Hant/
python3 gen_mac_06.py --lang zh-Hant --step win   # 2112×1262
python3 gen_mac_06.py --lang zh-Hant --step html  # .win 高度 1262
python3 gen_mac_06.py --lang zh-Hant --step export
```

繁体页的标题用 PingFang TC（`html/zh-Hant/06.html` 自带字体覆盖），
`我的項目 / 生成記錄自動留存 / 隨時回聽、重新匯出，波形與參數都在` 全部是繁体字形。

## 6. 顺带发现

`gen_previews.py` / `gen_ios_previews.py` 这些旧生成器**没进 git、已从工作区消失**，
`html/*.html` 里引用的 `1.png` `2.png` `3.png` `win-01/02/03.png` 也都不在了。
也就是说 01–05 现在**无法重新渲染**，只有成片是可信的。`win-06.png` 这次已经重新落盘。
