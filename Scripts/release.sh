#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
OUTPUT_DIR="${1:-${PROJECT_DIR}/outputs}"
INFO_PLIST="${PROJECT_DIR}/Resources/Info.plist"
CHANGELOG_PATH="${PROJECT_DIR}/CHANGELOG.md"
SPARKLE_BIN_DIR="${PROJECT_DIR}/Vendor/Sparkle/bin"
GENERATE_APPCAST="${SPARKLE_BIN_DIR}/generate_appcast"
APPCAST_SOURCE_DIR="$(mktemp -d /private/tmp/focusveilappcast.XXXXXX)"

trap 'rm -rf "${APPCAST_SOURCE_DIR}"' EXIT

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${INFO_PLIST}")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${INFO_PLIST}")"
TAG="v${VERSION}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-FocusVeil}"
DOWNLOAD_URL_PREFIX="${SPARKLE_DOWNLOAD_URL_PREFIX:-https://github.com/Steirch/FocusVeil/releases/download/${TAG}/}"
FULL_RELEASE_NOTES_URL="${SPARKLE_FULL_RELEASE_NOTES_URL:-https://github.com/Steirch/FocusVeil/blob/main/CHANGELOG.md}"
RELEASE_NOTES_PATH="${OUTPUT_DIR}/release-notes-${TAG}.md"
APPCAST_PATH="${OUTPUT_DIR}/appcast.xml"

if [[ ! -x "${GENERATE_APPCAST}" ]]; then
    echo "Missing ${GENERATE_APPCAST}" >&2
    exit 1
fi

zsh "${SCRIPT_DIR}/build.sh" "${OUTPUT_DIR}"

mkdir -p "${OUTPUT_DIR}" "${APPCAST_SOURCE_DIR}"

awk -v tag="${TAG}" '
    $0 == "## " tag {
        in_section = 1
        print
        next
    }
    in_section && /^## v[0-9]/ {
        exit
    }
    in_section {
        print
    }
' "${CHANGELOG_PATH}" > "${RELEASE_NOTES_PATH}"

if ! grep -q '[^[:space:]]' "${RELEASE_NOTES_PATH}"; then
    {
        echo "## ${TAG}"
        echo
        echo "FocusVeil ${VERSION} build ${BUILD_VERSION} release."
    } > "${RELEASE_NOTES_PATH}"
fi

ditto --norsrc "${OUTPUT_DIR}/FocusVeil.zip" "${APPCAST_SOURCE_DIR}/FocusVeil.zip"
install -m 644 "${RELEASE_NOTES_PATH}" "${APPCAST_SOURCE_DIR}/FocusVeil.md"

"${GENERATE_APPCAST}" \
    --account "${SPARKLE_ACCOUNT}" \
    --download-url-prefix "${DOWNLOAD_URL_PREFIX}" \
    --full-release-notes-url "${FULL_RELEASE_NOTES_URL}" \
    --link "https://github.com/Steirch/FocusVeil/releases/tag/${TAG}" \
    --embed-release-notes \
    -o "${APPCAST_PATH}" \
    "${APPCAST_SOURCE_DIR}"

echo "Built ${APPCAST_PATH}"
echo "Built ${RELEASE_NOTES_PATH}"
