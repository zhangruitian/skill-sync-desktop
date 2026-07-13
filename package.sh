#!/usr/bin/env bash
# =============================================================================
# package.sh — 将 SkillSyncDesktop 打包为可分发的 .dmg 安装包
#
# 用法:
#   ./package.sh              # 编译并打包，输出到 dist/
#   ./package.sh --sign CERT  # 使用指定证书签名
#   ./package.sh --notarize   # 签名 + 公证 (需要 keychain profile "notary")
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ============================== 配置 ======================================

APP_NAME="SkillSyncDesktop"
BUNDLE_ID="com.skillsync.desktop"
VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-$(date +%Y%m%d%H%M)}"
DIST_DIR="$SCRIPT_DIR/dist"
BUILD_DIR="$SCRIPT_DIR/.build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
DO_NOTARIZE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign) SIGN_IDENTITY="$2"; shift 2 ;;
        --notarize) DO_NOTARIZE=true; shift ;;
        --version) VERSION="$2"; shift 2 ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
done

# ============================== 工具函数 ====================================

step() { echo ""; echo -e "\033[1;34m→\033[0m $*"; }
ok()   { echo "   \033[32m✅\033[0m $*"; }
warn() { echo "   \033[33m⚠️\033[0m  $*"; }

# ============================== 构建 ========================================

echo "========================================="
echo "  SkillSyncDesktop — DMG 打包"
echo "  版本: $VERSION ($BUILD)"
echo "========================================="

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

# ---- 1. 编译 Swift ----
step "编译 Swift 源文件 (25 files)..."

swiftc -parse-as-library \
    -framework SwiftUI -framework Combine -framework AppKit \
    -target arm64-apple-macos13.0 \
    -o "$BUILD_DIR/$APP_NAME" \
    SkillSyncDesktop/App.swift \
    SkillSyncDesktop/SkillSyncViewModel.swift \
    SkillSyncDesktop/Models/AppSettings.swift \
    SkillSyncDesktop/Models/AgentConfig.swift \
    SkillSyncDesktop/Models/AppError.swift \
    SkillSyncDesktop/Models/DesignSystem.swift \
    SkillSyncDesktop/Models/HubProfile.swift \
    SkillSyncDesktop/Models/SkillInfo.swift \
    SkillSyncDesktop/Models/SyncState.swift \
    SkillSyncDesktop/Services/AgentManager.swift \
    SkillSyncDesktop/Services/BackupCleaner.swift \
    SkillSyncDesktop/Services/DiffEngine.swift \
    SkillSyncDesktop/Services/HubManager.swift \
    SkillSyncDesktop/Services/StatusEngine.swift \
    SkillSyncDesktop/Services/SyncEngine.swift \
    SkillSyncDesktop/Services/WatchEngine.swift \
    SkillSyncDesktop/Views/ContentView.swift \
    SkillSyncDesktop/Views/DiffView.swift \
    SkillSyncDesktop/Views/SettingsPageView.swift \
    SkillSyncDesktop/Views/SettingsView.swift \
    SkillSyncDesktop/Views/StatusView.swift \
    SkillSyncDesktop/Views/TerminalPageView.swift \
    SkillSyncDesktop/Views/TerminalView.swift \
    SkillSyncDesktop/Views/Components/SkillRow.swift \
    SkillSyncDesktop/Views/Components/StatusBadge.swift \
    2>&1

ok "编译完成: $BUILD_DIR/$APP_NAME"

# ---- 2. 创建 App Bundle ----
step "创建 App Bundle..."

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>   <string>zh-Hans</string>
    <key>CFBundleExecutable</key>           <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>           <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key>                 <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>          <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleShortVersionString</key>   <string>$VERSION</string>
    <key>CFBundleVersion</key>              <string>$BUILD</string>
    <key>LSMinimumSystemVersion</key>       <string>13.0</string>
    <key>NSHighResolutionCapable</key>      <true/>
    <key>NSHumanReadableCopyright</key>     <string>MIT License</string>
    <key>LSApplicationCategoryType</key>    <string>public.app-category.developer-tools</string>
    <key>CFBundleIconFile</key>             <string>AppIcon</string>
</dict>
</plist>
PLIST

echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# ---- 3. App Icon ----
ICON_DIR="$APP_BUNDLE/Contents/Resources"

if [[ -f "$SCRIPT_DIR/AppIcon.icns" ]]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$ICON_DIR/AppIcon.icns"
    ok "使用已有 AppIcon.icns"
elif [[ -f "/tmp/skillsync.icns" ]]; then
    cp /tmp/skillsync.icns "$ICON_DIR/AppIcon.icns"
    ok "使用 /tmp/skillsync.icns"
else
    warn "未找到 AppIcon.icns，使用无图标 bundle"
fi

ok "App Bundle 创建完成: $APP_BUNDLE"

# ---- 4. 代码签名 (可选) ----
if [[ -n "$SIGN_IDENTITY" ]]; then
    step "代码签名 (Identity: $SIGN_IDENTITY)..."

    ENTITLEMENTS="$SCRIPT_DIR/SkillSyncDesktop.entitlements"
    if [[ ! -f "$ENTITLEMENTS" ]]; then
        cat > "$ENTITLEMENTS" <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
    <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict></plist>
ENT
    fi

    codesign --force --options runtime --sign "$SIGN_IDENTITY" \
        --entitlements "$ENTITLEMENTS" "$APP_BUNDLE" 2>&1 || {
        warn "签名失败，将生成未签名 DMG"
        SIGN_IDENTITY=""
    }
    [[ -n "$SIGN_IDENTITY" ]] && ok "签名完成"
fi

# ---- 5. 创建 DMG ----
step "创建 DMG..."

DMG_TEMP="$BUILD_DIR/dmg_temp"
DMG_FILE="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"

rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

cp -R "$APP_BUNDLE" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_FILE" >/dev/null 2>&1

ok "DMG 创建完成"

# ---- 6. 设置 DMG 布局 ----
step "设置 DMG 窗口布局..."

DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_FILE" 2>&1 | grep -o '/Volumes/.*$' | head -1 || true)

if [[ -n "$DEVICE" ]]; then
    osascript <<APPLESCRIPT 2>/dev/null || true
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set status bar visible of container window to false
        set the bounds of container window to {400, 200, 940, 580}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set position of item "$APP_NAME.app" of container window to {165, 190}
        set position of item "Applications" of container window to {375, 190}
        close
        open
        update without registering applications
    end tell
end tell
APPLESCRIPT

    sleep 2
    hdiutil detach "$DEVICE" -quiet -force 2>/dev/null || true
    ok "DMG 布局设置完成"
else
    warn "无法挂载 DMG，跳过布局设置"
fi

# ---- 7. 签名 DMG 并公证 (可选) ----
if [[ -n "$SIGN_IDENTITY" ]]; then
    step "签名 DMG..."
    codesign --force --sign "$SIGN_IDENTITY" "$DMG_FILE" 2>/dev/null && ok "DMG 签名完成" || warn "DMG 签名失败"
fi

if $DO_NOTARIZE && [[ -n "$SIGN_IDENTITY" ]]; then
    step "提交公证..."
    ZIP_FILE="$DIST_DIR/$APP_NAME-notarize.zip"
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_FILE"
    xcrun notarytool submit "$ZIP_FILE" --keychain-profile "notary" --wait 2>&1 || warn "公证需要 keychain profile 'notary'"
    rm -f "$ZIP_FILE"
fi

# ---- 8. 验证打包结果 ----
step "验证打包结果"

DMG_SIZE=$(du -sh "$DMG_FILE" | cut -f1)
APP_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)

echo ""
echo "   App Bundle: $APP_BUNDLE ($APP_SIZE)"
echo "   DMG:        $DMG_FILE ($DMG_SIZE)"
echo "   文件数:     $(find "$APP_BUNDLE" -type f | wc -l) files"

# 快速验证 bundle 结构
for required in \
    "Contents/MacOS/$APP_NAME" \
    "Contents/Info.plist" \
    "Contents/PkgInfo"; do
    if [[ -e "$APP_BUNDLE/$required" ]]; then
        ok "$required"
    else
        warn "缺少: $required"
    fi
done

[[ -f "$ICON_DIR/AppIcon.icns" ]] && ok "AppIcon.icns" || warn "无图标"

echo ""
echo "========================================="
echo "  打包完成!"
echo "========================================="
echo ""
echo "  分发 DMG:  $DMG_FILE"
echo ""
echo "  用户双击 .dmg → 将 App 拖入 Applications → 完成安装"
echo ""

open -R "$DMG_FILE" 2>/dev/null || true
