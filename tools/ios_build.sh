#!/usr/bin/env bash
#
# 命令行构建 iOSEmora（iOS Simulator / arm64）。
#
#   bash tools/ios_build.sh            # 只编 iOS
#   bash tools/ios_build.sh mac        # 顺带回归 macOS 的 Emora
#
# —— 下面三个 workaround 都是**本机 CLI 沙箱**的限制，Xcode GUI 里直接 Build 不需要 ——
#
# 1) IDEPackageSupportDisableManifestSandbox
#    SwiftPM 编译 Package.swift 时会 sandbox_apply，在受限 shell 里被拒：
#      xcodebuild: error: Could not resolve package dependencies:
#        sandbox-exec: sandbox_apply: Operation not permitted
#    SwiftPM 没有对应的 CLI flag，只能靠这个 Xcode 内部开关。脚本写入后
#    会在退出时恢复原样（原本没有就删掉）。
#
# 2) OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox'
#    宏插件服务 swift-plugin-server 起不来：
#      error: external macro implementation type 'SwiftMacros.TaskLocalMacro'
#             could not be found for macro 'TaskLocal()'; ... produced malformed response
#    ⚠️ 必须写成 $(inherited) 追加：直接覆盖会丢掉 SPM 包自己的 -package-name 等参数，
#       supabase-swift 会报 "ambiguous implicit access level for import of 'HTTPTypes'"。
#
# 3) ONLY_ACTIVE_ARCH=YES
#    generic/platform=iOS Simulator 这种通用 destination 会同时编 arm64 + x86_64 两份，
#    纯属浪费时间（而且任一架构的第三方包失败都会让整体失败）。
#
set -euo pipefail

cd "$(dirname "$0")/.."
PROJ="EmotionVoice/EmotionVoice.xcodeproj"
DD_IOS="${IOS_DERIVED_DATA:-/tmp/iOSBuildDD}"
DD_MAC="${MAC_DERIVED_DATA:-/tmp/MacBuildDD}"
KEY="IDEPackageSupportDisableManifestSandbox"

# —— 开关 1：写入并在退出时恢复 ——
prev="$(defaults read com.apple.dt.Xcode "$KEY" 2>/dev/null || true)"
restore() {
  if [ -n "$prev" ]; then
    defaults write com.apple.dt.Xcode "$KEY" "$prev"
  else
    defaults delete com.apple.dt.Xcode "$KEY" 2>/dev/null || true
  fi
}
trap restore EXIT
defaults write com.apple.dt.Xcode "$KEY" -bool YES

FLAGS='OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox'

echo "▶ 构建 iOSEmora（iOS Simulator, arm64）"
xcodebuild -project "$PROJ" -scheme iOSEmora \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DD_IOS" -skipPackageUpdates \
  ONLY_ACTIVE_ARCH=YES "$FLAGS" build

if [ "${1:-}" = "mac" ]; then
  echo "▶ 回归构建 Emora（macOS）"
  xcodebuild -project "$PROJ" -scheme Emora \
    -sdk macosx -derivedDataPath "$DD_MAC" -skipPackageUpdates \
    ONLY_ACTIVE_ARCH=YES "$FLAGS" build
fi

echo "✅ 全部构建通过"
