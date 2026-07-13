#!/usr/bin/env bash
# =============================================================================
# setup-xcode.sh — 生成 Xcode 项目文件
# 使用 xcodegen 或手动创建 .xcodeproj 结构
# =============================================================================

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="SkillSyncDesktop"
BUNDLE_ID="com.skillsync.desktop"

cd "$PROJECT_DIR"

echo "========================================="
echo "  Skill Sync Desktop — Xcode 项目设置"
echo "========================================="
echo ""

# Method 1: Check for xcodegen
if command -v xcodegen &>/dev/null; then
    echo "✅ 检测到 xcodegen，使用 project.yml 生成项目..."

    cat > "$PROJECT_DIR/project.yml" <<YML
name: $APP_NAME
options:
  bundleIdPrefix: com.skillsync
  deploymentTarget:
    macOS: "13.0"
  xcodeVersion: "15.0"

settings:
  base:
    SWIFT_VERSION: "5.9"

targets:
  $APP_NAME:
    type: application
    platform: macOS
    sources:
      - $APP_NAME
    settings:
      base:
        INFOPLIST_FILE: $APP_NAME/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: $BUNDLE_ID
        GENERATE_INFOPLIST_FILE: NO
    info:
      path: $APP_NAME/Info.plist
YML

    xcodegen generate
    echo "✅ Xcode 项目已生成: ${APP_NAME}.xcodeproj"
    echo ""
    echo "打开项目: open ${APP_NAME}.xcodeproj"

# Method 2: Fallback — create minimal project via Swift Package Manager + xcodebuild
elif command -v xcodebuild &>/dev/null; then
    echo "⚠️  未检测到 xcodegen，使用 xcodebuild 方式..."
    echo ""

    # Create a minimal project using xcodebuild
    # This creates a basic macOS app target
    cat > "$PROJECT_DIR/build.sh" <<'BUILDSCRIPT'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

echo "正在编译 Skill Sync Desktop..."
swiftc -o SkillSyncDesktop \
    -framework SwiftUI \
    -framework Combine \
    -framework AppKit \
    -target arm64-apple-macos13.0 \
    -sdk $(xcrun --show-sdk-path --sdk macosx) \
    SkillSyncDesktop/App.swift \
    SkillSyncDesktop/SkillSyncViewModel.swift \
    SkillSyncDesktop/Models/SyncState.swift \
    SkillSyncDesktop/Models/AgentConfig.swift \
    SkillSyncDesktop/Models/SkillInfo.swift \
    SkillSyncDesktop/Models/AppSettings.swift \
    SkillSyncDesktop/Services/HubManager.swift \
    SkillSyncDesktop/Services/AgentManager.swift \
    SkillSyncDesktop/Services/StatusEngine.swift \
    SkillSyncDesktop/Services/SyncEngine.swift \
    SkillSyncDesktop/Services/DiffEngine.swift \
    SkillSyncDesktop/Services/WatchEngine.swift \
    SkillSyncDesktop/Services/BackupCleaner.swift \
    SkillSyncDesktop/Views/Components/StatusBadge.swift \
    SkillSyncDesktop/Views/Components/SkillRow.swift \
    SkillSyncDesktop/Views/StatusView.swift \
    SkillSyncDesktop/Views/DiffView.swift \
    SkillSyncDesktop/Views/SettingsView.swift \
    SkillSyncDesktop/Views/ContentView.swift \
    2>&1 || {
    echo ""
    echo "========================================="
    echo "  直接 swiftc 编译可能失败。"
    echo "  推荐方式：在 Xcode 中创建新项目并导入源文件。"
    echo "  详见下方的 Xcode 手动设置说明。"
    echo "========================================="
    exit 1
}

echo "✅ 编译完成: ./SkillSyncDesktop"
BUILDSCRIPT
    chmod +x "$PROJECT_DIR/build.sh"

    echo ""
    echo "========================================="
    echo "  推荐设置方式"
    echo "========================================="
    echo ""
    echo "方式 1 — 安装 xcodegen 后重新运行此脚本:"
    echo "  brew install xcodegen"
    echo "  ./setup-xcode.sh"
    echo ""
    echo "方式 2 — 手动在 Xcode 中创建项目:"
    echo "  1. 打开 Xcode → File → New → Project → macOS → App"
    echo "  2. Product Name: ${APP_NAME}"
    echo "  3. Interface: SwiftUI, Language: Swift"
    echo "  4. 保存到任意位置"
    echo "  5. 将 ${PROJECT_DIR}/${APP_NAME}/ 下的所有 .swift 文件拖入项目"
    echo "  6. 删除 Xcode 自动生成的 ContentView.swift 和 ${APP_NAME}App.swift"
    echo "  7. Build & Run (⌘R)"
    echo ""

else
    echo "❌ 未检测到 xcodegen 或 xcodebuild。"
    echo "   请安装 Xcode 或 Xcode Command Line Tools。"
    exit 1
fi
