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
- **light mode 适配**：当前颜色块对暗色 OK，亮色需要调一下。

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
