#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Presto"
BUNDLE_ID="${BUNDLE_ID:-io.github.phss97.presto}"
DIST_DIR="${ROOT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

BUNDLE_MODEL=0
CUSTOM_MODEL_FILE=""
INSTALL_APP=0
INSTALL_DIR="/Applications"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle-model)
      BUNDLE_MODEL=1
      if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
        CUSTOM_MODEL_FILE="$2"
        shift
      fi
      shift
      ;;
    --install)
      INSTALL_APP=1
      if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
        INSTALL_DIR="$2"
        shift
      fi
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--bundle-model [path/to/model.gguf]] [--install [/Applications]]" >&2
      exit 1
      ;;
  esac
done

"${ROOT_DIR}/scripts/setup-llamacpp.sh"

echo "Building ${APP_NAME} (release)..."
cd "${ROOT_DIR}"
swift build --disable-sandbox -c release

BIN_PATH="$(swift build --disable-sandbox -c release --show-bin-path)"
EXECUTABLE_SRC="${BIN_PATH}/${APP_NAME}"

if [[ ! -f "${EXECUTABLE_SRC}" ]]; then
  echo "Error: Built binary not found at ${EXECUTABLE_SRC}" >&2
  exit 1
fi

echo "Assembling ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${FRAMEWORKS_DIR}" "${RESOURCES_DIR}"

cp "${EXECUTABLE_SRC}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# Ensure @executable_path/../Frameworks rpath is present (ignore duplicate error if already linked)
install_name_tool -add_rpath "@executable_path/../Frameworks" "${MACOS_DIR}/${APP_NAME}" 2>/dev/null || true

LLAMA_FRAMEWORK_SRC="${ROOT_DIR}/Vendor/llama.xcframework/macos-arm64_x86_64/llama.framework"
if [[ ! -d "${LLAMA_FRAMEWORK_SRC}" ]]; then
  LLAMA_FRAMEWORK_SRC="$(find "${ROOT_DIR}/Vendor/llama.xcframework" -maxdepth 2 -name "llama.framework" -path "*macos*" | head -n 1)"
fi

if [[ -z "${LLAMA_FRAMEWORK_SRC}" || ! -d "${LLAMA_FRAMEWORK_SRC}" ]]; then
  echo "Error: macOS slice of llama.framework not found in Vendor/llama.xcframework" >&2
  exit 1
fi

cp -R "${LLAMA_FRAMEWORK_SRC}" "${FRAMEWORKS_DIR}/llama.framework"

echo "Generating AppIcon.icns..."
mkdir -p "${ROOT_DIR}/.build"
swiftc -parse-as-library \
  "${ROOT_DIR}/Sources/Presto/UI/PrestoBrandIcon.swift" \
  "${ROOT_DIR}/scripts/generate-icon.swift" \
  -o "${ROOT_DIR}/.build/generate-icon"
"${ROOT_DIR}/.build/generate-icon" "${RESOURCES_DIR}/AppIcon.icns"

if [[ "${BUNDLE_MODEL}" -eq 1 ]]; then
  mkdir -p "${RESOURCES_DIR}/Models"
  DEFAULT_MODEL_NAME="HY-MT1.5-1.8B-Q4_K_M.gguf"
  DEFAULT_MODEL_URL="https://huggingface.co/tencent/HY-MT1.5-1.8B-GGUF/resolve/main/${DEFAULT_MODEL_NAME}?download=true"

  if [[ -n "${CUSTOM_MODEL_FILE}" ]]; then
    if [[ ! -f "${CUSTOM_MODEL_FILE}" ]]; then
      echo "Error: Specified GGUF model not found: ${CUSTOM_MODEL_FILE}" >&2
      exit 1
    fi
    echo "Bundling custom model $(basename "${CUSTOM_MODEL_FILE}") into app resources..."
    cp "${CUSTOM_MODEL_FILE}" "${RESOURCES_DIR}/Models/$(basename "${CUSTOM_MODEL_FILE}")"
  else
    CACHED_MODEL="${HOME}/Library/Application Support/Presto/Models/${DEFAULT_MODEL_NAME}"
    if [[ -f "${CACHED_MODEL}" ]]; then
      echo "Copying cached ${DEFAULT_MODEL_NAME} into app resources..."
      cp "${CACHED_MODEL}" "${RESOURCES_DIR}/Models/${DEFAULT_MODEL_NAME}"
    else
      echo "Downloading ${DEFAULT_MODEL_NAME} (~1.1 GB) into app bundle..."
      curl -fL --progress-bar "${DEFAULT_MODEL_URL}" -o "${RESOURCES_DIR}/Models/${DEFAULT_MODEL_NAME}"
    fi
  fi
fi

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# Ad-hoc signatures change with every build, so macOS forgets the Accessibility grant
# after each reinstall. A stable self-signed certificate keeps the grant across rebuilds.
SIGN_IDENTITY="${PRESTO_SIGN_IDENTITY:-Presto Local Signing}"
if ! security find-identity -p codesigning | grep -q "\"${SIGN_IDENTITY}\""; then
  echo "Warning: signing identity \"${SIGN_IDENTITY}\" not found; using an ad-hoc signature." >&2
  echo "         Accessibility permission will need to be re-granted after each install." >&2
  SIGN_IDENTITY="-"
fi

echo "Signing ${APP_BUNDLE} (identity: ${SIGN_IDENTITY})..."
codesign --force --sign "${SIGN_IDENTITY}" "${FRAMEWORKS_DIR}/llama.framework"
codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"
touch "${APP_BUNDLE}"

echo "Built and signed: ${APP_BUNDLE}"

if [[ "${INSTALL_APP}" -eq 1 ]]; then
  INSTALLED_BUNDLE="${INSTALL_DIR}/${APP_NAME}.app"
  echo "Installing to ${INSTALLED_BUNDLE}..."
  pkill -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
  sleep 0.3
  rm -rf "${INSTALLED_BUNDLE}"
  ditto "${APP_BUNDLE}" "${INSTALLED_BUNDLE}"
  touch "${INSTALLED_BUNDLE}"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${INSTALLED_BUNDLE}" 2>/dev/null || true
  echo "Installed: ${INSTALLED_BUNDLE}"
fi
