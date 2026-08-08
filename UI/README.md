# EmotionVoice UI 设计预览

> macOS 原生情感语音创作平台  
> 设计语言: Cold Luxury (冷调深色 + 琥珀金强调色)

---

## 📂 设计文件索引

| # | 文件 | 描述 |
|---|------|------|
| 1 | [homepage.html](./homepage.html) | **首页** - Hero + 快速开始 + 最近项目 + 本月统计 |
| 2 | [voice-studio.html](./voice-studio.html) | **语音合成工作台** - 核心功能页（文本编辑 + 情感控制 + 生成） |
| 3 | [voices.html](./voices.html) | **音色库** - 500+ 音色浏览 + 试听 + 收藏 |
| 4 | [projects.html](./projects.html) | **项目管理** - 项目列表 + 状态分组 + 进度跟踪 |
| 5 | [credits.html](./credits.html) | **积分中心** - 余额 + 套餐 + 消费明细 |
| 6 | [settings.html](./settings.html) | **设置** - 模型/快捷键/外观/文件配置 |

---

## 🎨 设计系统总览

### 色彩系统 (Cold Luxury)

```
背景层 (深色)
├─ #0E0F12  ████  主背景
├─ #15171B  ▓▓▓▓  次背景
├─ #1C1F24  ▒▒▒▒  卡片底
└─ #22262D  ░░░░  悬浮层

强调色 (琥珀金 - 区别于AI紫)
├─ #E8A968  ████  主强调 (CTA)
├─ #D49B5B  ▓▓▓▓  次强调
└─ #F2C088  ▒▒▒▒  高亮

文字层级
├─ #F5F5F7  ████  主文字
├─ #A8ABB4  ▓▓▓▓  次文字
└─ #6B6E76  ▒▒▒▒  弱化文字

状态色
├─ #6BB87A  ✓ 成功
├─ #E8A968  ⚠ 警告
├─ #D96D6D  ✗ 错误
└─ #6B8BC9  ℹ 信息
```

### 圆角系统

```
8px   按钮、小标签
12px  输入框、小卡片
16px  主卡片、面板
20px  大容器
999px 胶囊按钮
```

### 字体

```
SF Pro Display  标题 (系统字体)
SF Pro Text     正文
SF Mono         数字、字符数、积分
```

---

## 🖼️ 界面架构

### 通用布局

```
┌─────────────────────────────────────────────┐
│ 🔴 🟡 🟢    EmotionVoice         [⚙️] [🔍] │ ← Title Bar (52px)
├─────────────┬───────────────────────────────┤
│  🏠 首页    │  breadcrumb        [按钮组]    │ ← Top Toolbar
│  🎤 语音    │  ─────────────────────────── │
│  🎭 音色    │                               │
│             │  ┌─ Content Card ────────┐   │
│  ─────      │  │                       │   │
│  我的项目    │  │  Page Content         │   │
│  📁 有声书  │  │                       │   │
│  📁 播客    │  └───────────────────────┘   │
│             │                               │
│  ─────      │  ┌─ Content Card ────────┐   │
│  💎 积分    │  │                       │   │
│  📊 统计    │  │                       │   │
│  ⚙️ 设置    │  └───────────────────────┘   │
│             │                               │
│  ┌──────┐   │                               │
│  │💎1280│   │                               │
│  └──────┘   │                               │
└─────────────┴───────────────────────────────┘
   220px              Flex
   Sidebar           Main Content
```

---

## ✅ Pre-Flight Check (设计原则)

| 检查项 | 状态 |
|--------|------|
| 无 em-dash (`—`) | ✅ |
| 全页暗色模式统一 | ✅ |
| 单一强调色 (琥珀金) | ✅ |
| 全局圆角系统 | ✅ |
| 无 Inter 字体 | ✅ (用 SF Pro) |
| 无暖米色+陶土色 | ✅ (用 Cold Luxury) |
| 无 3 列等宽卡片 | ✅ |
| 真实场景数据 | ✅ |
| 无版本号 eyebrow | ✅ |
| 无 scroll cue | ✅ |
| 无装饰文字带 | ✅ |

---

## 🚀 快速预览

```bash
# 在浏览器中打开任一文件
open /Users/young/Resource/EmotionVoice/UI/homepage.html
open /Users/young/Resource/EmotionVoice/UI/voice-studio.html
open /Users/young/Resource/EmotionVoice/UI/voices.html
open /Users/young/Resource/EmotionVoice/UI/projects.html
open /Users/young/Resource/EmotionVoice/UI/credits.html
open /Users/young/Resource/EmotionVoice/UI/settings.html
```

---

## 📋 页面功能对应表

| 页面 | 主要功能 | 关键交互 |
|------|----------|----------|
| **首页** | 概览、快捷入口、最近项目、本月统计 | 4个数据卡 + 3个快捷入口 + 4个项目 |
| **语音合成** | 文本输入、情感控制、音色选择、生成导出 | 左侧编辑 + 右侧配置 + 情感网格 |
| **音色库** | 500+ 音色浏览、试听、收藏、分类筛选 | 5个分类 + 试听波形 + 使用按钮 |
| **项目管理** | 项目列表、状态分组、进度跟踪、批量管理 | 列表视图 + 状态过滤 + 进度条 |
| **积分中心** | 余额查询、套餐购买、消费明细、趋势分析 | 4个套餐 + 图表 + 交易记录 |
| **设置** | 模型选择、快捷键、外观、文件配置 | 双栏导航 + 设置项列表 |

---

## 🎯 后续优化方向

- [ ] 添加 SwiftUI 代码生成（实际开发用）
- [ ] 创建设计 token 文件（颜色、间距、字体变量）
- [ ] 添加 loading / empty / error 状态
- [ ] 创建 dark/light mode 切换预览
- [ ] 添加音频波形交互细节（hover、click 状态）
- [ ] 制作组件库文档（按钮、卡片、表单）