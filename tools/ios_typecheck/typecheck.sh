#!/bin/bash
#
# iOS 端类型检查（本机 xcodebuild 被沙箱挡住 SPM 包解析时的替代方案）
#
#   cd <repo root> && bash tools/ios_typecheck/typecheck.sh
#
# 说明：
#  - 只做 `swiftc -typecheck`，不产出二进制；
#  - 依赖 SPM 包（SQLite / Supabase / KeychainSwift）的 6 个服务文件被
#    `tools/ios_typecheck/Shims.swift` 里的同签名替身取代，
#    真机 / 模拟器编译仍走 Xcode + 真包，两者互不影响。
#  - `-disable-sandbox` 必加：否则 SwiftUI 宏插件服务会报错。
#
set -u
cd "$(dirname "$0")/../.." || exit 1

ROOT=$(pwd)
E="$ROOT/EmotionVoice/EmotionVoice"
# ⚠️ iOS 端代码在 `View/iOS`（`EmotionVoice/iOSEmora` 那棵空目录是历史遗留，别再指它）
IOSENTRY="$E/View/iOS"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)

LIST=$(mktemp)
trap 'rm -f "$LIST"' EXIT

# 依赖 SPM 包、被 Shims.swift 顶替掉的 6 个文件（改了目录结构要同步维护这份清单）
SHIMMED="DatabaseManager VoiceService ProjectService CreditsService SupabaseManager DeviceIdentifier"

{
  # ---- iOS 端代码 ----
  find "$IOSENTRY" -name "*.swift" | sort

  # ---- 复用的既有逻辑（Shared/ 下全部，剔除上面那 6 个）----
  find "$E/Shared" -name "*.swift" | sort | while read -r f; do
    base=$(basename "$f" .swift)
    skip=0
    for s in $SHIMMED; do [ "$base" = "$s" ] && skip=1; done
    [ "$skip" -eq 0 ] && echo "$f"
  done

  # ---- iOS 与 macOS 共用的模型 / 组件（在 View/macOS 下，但进了 iOS target）----
  echo "$E/View/macOS/VoiceStudioView/EmotionToken/TTSContentItem.swift"
  echo "$E/View/macOS/DataReceiveGridView.swift"
  echo "$E/View/macOS/FlowLayout.swift"

  # ---- 替身 ----
  echo "$ROOT/tools/ios_typecheck/Shims.swift"
} > "$LIST"

swiftc -typecheck -disable-sandbox \
  -swift-version 5 \
  -target arm64-apple-ios18.6-simulator \
  -sdk "$SDK" \
  @"$LIST"
