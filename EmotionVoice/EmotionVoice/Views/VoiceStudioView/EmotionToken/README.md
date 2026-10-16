# EmotionTokenEditor — 验证步骤

Demo 入口：左侧 Sidebar -> **Token Demo (Dev)**

## 核心交互要求

### ✅ 必须通过的测试场景

| # | 场景 | 操作 | 期望 |
|---|------|------|------|
| 1 | "你好 [开心] 世界" | Backspace | `[开心]` 整体删除，光标停在「你好 」末尾 |
| 2 | "[开心] 你好" | Backspace | `[开心]` 整体删除 |
| 3 | "你好 [开心]" | Backspace | `[开心]` 整体删除 |
| 4 | "[开心][悲伤][兴奋]" | 连续 Backspace × 3 | 三个 token 都被整体删除 |
| 5 | "你好 [开心] 世界 [悲伤] 测试" | 任意 Backspace | 整体删除目标 token |
| 6 | 任意修改后 Cmd+Z ⇧Cmd+Z | | 完整 Undo / Redo |

### ✅ 额外行为

- **× 按钮**：点击 Token 右上角的 × 整体删除该 Token
- **多行**：可换行编辑（具体操作：在编辑器内按 Enter）
- **点击 Token 本体**：选中 Token（选中态显示在编辑器底部预览中）
- **拖动 + 复制粘贴**：复制跨文本 + Token 时保留 Token 结构（实验）

## 导出格式

Demo 底部实时显示三个派生数据：

1. **API 字符串** — `你好[happy]天气真不错[excited]我们出去玩吧。`
   即 `toTTSAPIString()`，交给后端的最终字符串。
2. **Display 字符串** — `你好 [😊 开心] 天气真不错`
   人类查看用，对应 `toDisplayString()`。
3. **JSON** — `[{"type":"text","content":"你好"},{"type":"emotion","content":"开心","emoji":"😊","englishTag":"happy"}]`
   对应 `[TTSContentItem]` 的序列化结果。

## 视觉设计（v13 · 语气胶囊版）

设计稿：`UI/emotion_token_editor_capsule.html`

| 元素 | 形态 |
|------|------|
| 语气标签 | 作用域的**整段文本**包进同色胶囊（填充 13%、1px 内描边 42%、圆角 9、内边距 8×6） |
| 徽章 | emoji + 名称（10.5pt 加粗）压在胶囊**左上角**（向上探出 14），底色 = 编辑器背景 + 情绪色描边；只在首块出现 |
| 跨行 | 胶囊按**行片段**分块绘制，每块各自圆角（对应 CSS `box-decoration-break: clone`） |
| 拟声效果 | 仍是点插入的虚线声音标记（12pt、圆角 6、内边距 7×1.5，左右各内缩 3），嵌在语气胶囊内部、不打断它 |
| 接缝 | 任意两块（胶囊↔胶囊、胶囊↔拟声）之间恒定留 2pt 净间隙；行距 28、顶部留白 28 |
| 删除 | 悬停胶囊 / 徽章 → 徽章右侧浮出 ×；拟声 → 正中浮出 ×；两者都支持选中 + `⌫` |

### 绘制顺序（关键，顺序**不能换**）

`EmotionTokenTextView.draw(_:)` 分三步：

1. `drawToneCapsules` — 胶囊必须在字形**下面**，否则会盖住正文；
2. `drawToneBadges` — 徽章。**必须画在 `super.draw` 之前**，见下面的坑；
3. `super.draw(rect)` — 文本 / 拟声附件（拟声 pill 自然叠在胶囊之上）。

配套前提：`tokenView.drawsBackground = false`（见 `EmotionTokenEditor`）。
NSTextView 默认会刷一层背景，那层在第 3 步里画，会把第 1 步铺好的胶囊整片盖掉。

#### ⚠️ 为什么徽章必须在 `super.draw` 之前

实测 `super.draw(rect)` 返回后，图形状态里的**裁剪被收窄到文本容器区域**
（从 container origin 开始）。徽章恰恰画在容器上沿**之外**（container y 为负），
放在最后画会整块被裁掉 —— 胶囊在容器内、v12 的下划线也在容器内，
所以当时只有徽章凭空消失，极难排查。离屏渲染验证：提前画即可完整显示。

徽章提前画之所以安全，是因为它**不与任何字形相交**：徽章底边（capsuleTop + 5）
比首行字形顶端（capsuleTop + 6.5）还高 1.5pt；行距 28 下也不会压到上一行的胶囊 / 拟声。
它只会盖住自己那条胶囊的上沿 —— 这正是设计要的效果。

### 几何陷阱

- `boundingRect(forGlyphRange:in:)` 的高度是**整行**高（含 lineSpacing），只有 `x / width` 可信；
  胶囊的上下沿必须由 `baseline ± font.ascender/descender` 推出来。
- 徽章向上探出 `badgeTopOffset` = 14，首行因此要求 `textContainerInset.height` = 28，否则被容器裁掉。
  另有一层兜底：`toneBadgeLayout` 的 `minY` 会把徽章压回可见区（宁可多盖一点胶囊）。
- **语气标记宽 5pt 而不是 1pt**：它是相邻两个作用域之间唯一的物理间距。1pt 时两段作用域文本
  几乎贴死，两侧 8pt 内边距必然重叠，再怎么收敛都切不出缝隙；5pt（≈1/3 个汉字）后
  `resolveCapsuleSeams` 才切得出真正的 `capsuleSeamGap` = 2pt 间隙。
  这就是设计稿 `margin: 0 4px`（两段共 8px）在 AppKit 里的等价物。
- 拟声 pill 的 **advance 宽度不变，但只画在中间**（左右各内缩 `soundEdgeInset` = 3）。
  否则胶囊的 8pt 内边距会压到 pill 底下，从它半透明的填充里透出一道重叠的描边。
  接缝计算用的是这个内缩后的矩形（`soundMarkerFrames()`），不是 cell 的完整 frame。
- 空作用域的锚点要取标记的**右边缘**（`loc.x + cellWidth`），取左边缘会和上一段文本末尾重合，
  接缝同样切不出间隙。

## 已实现

- [x] `TTSContentItem`：enum + Codable
- [x] `EmotionTokenAttachment`：NSTextAttachment 子类
- [x] `EmotionTokenAttachmentCell`：自绘 Capsule UI + × 按钮 + Token 选中态
- [x] `EmotionTokenTextView`：NSTextView 子类，原子删除逻辑
- [x] `EmotionTokenEditor`：NSViewRepresentable，绑定 [TTSContentItem]
- [x] `EmotionTokenEditorDemoView` + DemoViewModel

## 待改进（不影响第一阶段验收）

- **IME（中文/日文/韩文输入法）marked text 时的样式刷新**：先不处理。
- **拖拽**：可以加专门的拖拽支持（NSPasteboardItemType + 拖拽图标）。
- **替换 Token**：当前只支持删除再插入；可以加「修改 Token」入口。
- **light mode 适配**：颜色已由 `EmotionTokenStyle.resolved(for:dark:)` 明/暗双解析（亮色压暗 40%），
  徽章底色也跟着走；但整体尚未在亮色外观下逐项目视校验。

## 关键文件路径

```
EmotionVoice/EmotionVoice/Views/VoiceStudioView/EmotionToken/
├── TTSContentItem.swift                       # 数据模型
├── EmotionTokenAttachment.swift               # NSTextAttachment 包装
├── EmotionTokenStyle.swift                    # 视觉样式
├── EmotionTokenAttachmentCell.swift           # 自绘 Cell
├── EmotionTokenTextView.swift                 # NSTextView 子类
├── EmotionTokenEditor.swift                   # NSViewRepresentable 桥接
├── EmotionTokenEditorDemoViewModel.swift      # Demo VM
└── EmotionTokenEditorDemoView.swift           # Demo 页面
```

## 集成步骤（待用户确认 Demo 后）

1. 把 `EmotionTokenEditor` 嵌入 `VoiceStudioView.swift` 的 `textEditorCard` 部分
2. 把 `VoiceStudioViewModel.insertEmotion(tag:)` 改为推送 [TTSContentItem]
3. 把 `vm.text` 改为 `vm.items: [TTSContentItem]`
4. 把生成时的 `ttsText` 提取改为 `vm.items.toTTSAPIString()`
