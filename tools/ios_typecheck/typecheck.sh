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
IOSENTRY="$ROOT/EmotionVoice/iOSEmora"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)

LIST=$(mktemp)
trap 'rm -f "$LIST"' EXIT

{
  # ---- iOS 端新代码（iOS/ 目录已迁到 EmotionVoice/iOSEmora）----
  find "$IOSENTRY" -name "*.swift" | sort

  # ---- 复用的既有逻辑（不含依赖 SPM 包的 6 个服务）----
  echo "$E/Models/AudioItem.swift"
  echo "$E/Models/BasicVoiceTemplate.swift"
  echo "$E/Models/Constants.swift"
  echo "$E/Models/ConsumptionRecord.swift"
  echo "$E/Models/PurchaseRecord.swift"
  echo "$E/Models/Voice.swift"
  echo "$E/Models/VoiceCatalog.swift"
  echo "$E/Helper/Const.swift"
  echo "$E/Helper/Func.swift"
  echo "$E/Helper/TextSplitter.swift"
  echo "$E/Extension/AudioConcatenator.swift"
  echo "$E/Extension/AudioDuration.swift"
  echo "$E/Extension/Formatters.swift"
  echo "$E/Extension/String+Extension.swift"
  echo "$E/Services/AudioPreviewPlayer.swift"
  echo "$E/Services/BailianTTSService.swift"
  echo "$E/Services/BasicVoiceLoader.swift"
  echo "$E/Services/RegionConfig.swift"
  echo "$E/Services/TTSEndpoint.swift"
  echo "$E/Store/CreditManager.swift"
  echo "$E/Store/StoreKitManager.swift"
  echo "$E/Supabase/DeviceInfo.swift"
  echo "$E/Supabase/UserCreditsModel.swift"
  echo "$E/ViewModels/AppState.swift"
  echo "$E/ViewModels/HistoryViewModel.swift"
  echo "$E/ViewModels/VoicesLibraryViewModel.swift"
  echo "$E/ViewModels/VoiceStudioViewModel.swift"
  echo "$E/Views/DataReceiveGridView.swift"
  echo "$E/DesignSystem/AppColor.swift"
  echo "$E/DesignSystem/AppFont.swift"
  echo "$E/DesignSystem/AppRadius.swift"
  echo "$E/DesignSystem/View+Extension.swift"
  echo "$E/Views/FlowLayout.swift"
  echo "$E/Views/VoiceStudioView/EmotionToken/TTSContentItem.swift"

  # ---- 替身 ----
  echo "$ROOT/tools/ios_typecheck/Shims.swift"
} > "$LIST"

swiftc -typecheck -disable-sandbox \
  -swift-version 5 \
  -target arm64-apple-ios18.6-simulator \
  -sdk "$SDK" \
  @"$LIST"
