#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
OUTPUT_DIR="${1:-${PROJECT_DIR}/outputs}"
BUILD_DIR="$(mktemp -d /private/tmp/focusveilbuild.XXXXXX)"
APP_DIR="${BUILD_DIR}/FocusVeil.app"
ARCHIVE_PATH="${OUTPUT_DIR}/FocusVeil.zip"
DMG_PATH="${OUTPUT_DIR}/FocusVeil.dmg"
DMG_STAGING_DIR="${BUILD_DIR}/dmg"
DMG_STAGING_APP_DIR="${DMG_STAGING_DIR}/FocusVeil.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
MODULE_CACHE_DIR="${PROJECT_DIR}/work/clang-module-cache"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
CLANG_PATH="$(xcrun --find clang)"

trap 'rm -rf "${BUILD_DIR}"' EXIT

cd "${PROJECT_DIR}"

mkdir -p "${OUTPUT_DIR}" "${MACOS_DIR}" "${RESOURCES_DIR}" "${MODULE_CACHE_DIR}"

CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" \
"${CLANG_PATH}" \
    -fobjc-arc \
    -fmodules \
    -Os \
    -mmacosx-version-min=13.0 \
    -isysroot "${SDK_PATH}" \
    "Sources/FocusVeil/main.m" \
    -framework AppKit \
    -framework ApplicationServices \
    -framework ServiceManagement \
    -o "${MACOS_DIR}/FocusVeil"

install -m 644 "Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
install -m 644 "Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"

xattr -cr "${APP_DIR}"
codesign --force --deep --sign - "${APP_DIR}"
codesign --verify --deep --strict "${APP_DIR}"

rm -f "${ARCHIVE_PATH}" "${DMG_PATH}"
ditto -c -k --norsrc --keepParent "${APP_DIR}" "${ARCHIVE_PATH}"

mkdir -p "${DMG_STAGING_DIR}"
ditto --norsrc "${APP_DIR}" "${DMG_STAGING_APP_DIR}"
ln -s /Applications "${DMG_STAGING_DIR}/Applications"
hdiutil create \
    -volname "FocusVeil" \
    -srcfolder "${DMG_STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}" >/dev/null

echo "Built ${ARCHIVE_PATH}"
echo "Built ${DMG_PATH}"
