#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RVE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKSPACE_DIR="$(cd "${RVE_DIR}/.." && pwd)"

APP_NAME="RhizoVisionExplorer"
APP_EXECUTABLE_DEFAULT="${WORKSPACE_DIR}/build/repro_x64/rhizovisionexplorer/RhizoVisionExplorer"
CLI_EXECUTABLE_DEFAULT="${WORKSPACE_DIR}/build/repro_x64/rhizovisionexplorer/rv"
INSTALL_PREFIX_DEFAULT="${WORKSPACE_DIR}/_install/repro_x64"
ENV_PREFIX_DEFAULT="${HOME}/.conda/envs/rhizovision-compat-x64"
OUTPUT_ROOT_DEFAULT="${WORKSPACE_DIR}/release/macos"
CONDA_EXE="${CONDA_EXE:-conda}"

APP_EXECUTABLE="${APP_EXECUTABLE_DEFAULT}"
CLI_EXECUTABLE="${CLI_EXECUTABLE_DEFAULT}"
INSTALL_PREFIX="${INSTALL_PREFIX_DEFAULT}"
ENV_PREFIX="${ENV_PREFIX_DEFAULT}"
OUTPUT_ROOT="${OUTPUT_ROOT_DEFAULT}"
VERSION_OVERRIDE=""
CLEAN=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Create a distributable, self-contained macOS app bundle for end users.

Options:
  --app-executable PATH   Path to GUI executable (default: ${APP_EXECUTABLE_DEFAULT})
  --cli-executable PATH   Path to CLI executable (default: ${CLI_EXECUTABLE_DEFAULT})
  --install-prefix PATH   Install prefix containing cvutil libs (default: ${INSTALL_PREFIX_DEFAULT})
  --env-prefix PATH       Conda env prefix containing Qt/OpenCV libs (default: ${ENV_PREFIX_DEFAULT})
  --output-root PATH      Output root folder (default: ${OUTPUT_ROOT_DEFAULT})
  --version VERSION       Override app version (default: parsed from CMakeLists.txt)
  --clean                 Remove output root before packaging
  -h, --help              Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app-executable) APP_EXECUTABLE="$2"; shift ;;
        --cli-executable) CLI_EXECUTABLE="$2"; shift ;;
        --install-prefix) INSTALL_PREFIX="$2"; shift ;;
        --env-prefix) ENV_PREFIX="$2"; shift ;;
        --output-root) OUTPUT_ROOT="$2"; shift ;;
        --version) VERSION_OVERRIDE="$2"; shift ;;
        --clean) CLEAN=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
    shift
done

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This packaging script must run on macOS." >&2
    exit 1
fi

if [[ ! -x "${APP_EXECUTABLE}" ]]; then
    echo "App executable not found or not executable: ${APP_EXECUTABLE}" >&2
    exit 1
fi

if [[ ! -d "${INSTALL_PREFIX}/lib" ]]; then
    echo "Install prefix lib directory not found: ${INSTALL_PREFIX}/lib" >&2
    exit 1
fi

if [[ ! -d "${ENV_PREFIX}/lib" ]]; then
    echo "Conda env lib directory not found: ${ENV_PREFIX}/lib" >&2
    exit 1
fi

MACDEPLOYQT="${ENV_PREFIX}/lib/qt6/bin/macdeployqt"
if [[ ! -x "${MACDEPLOYQT}" ]]; then
    if command -v macdeployqt >/dev/null 2>&1; then
        MACDEPLOYQT="$(command -v macdeployqt)"
    else
        echo "macdeployqt not found. Expected at ${ENV_PREFIX}/lib/qt6/bin/macdeployqt." >&2
        exit 1
    fi
fi

if [[ -n "${VERSION_OVERRIDE}" ]]; then
    APP_VERSION="${VERSION_OVERRIDE}"
else
    APP_VERSION="$(sed -n 's/.*project([^ ]* VERSION \([0-9][0-9.]*\).*/\1/p' "${RVE_DIR}/CMakeLists.txt" | head -n1)"
    if [[ -z "${APP_VERSION}" ]]; then
        APP_VERSION="0.0.0"
    fi
fi

APP_ARCH="$(lipo -archs "${APP_EXECUTABLE}" | awk '{print $1}')"
RELEASE_ID="${APP_NAME}-macOS-${APP_VERSION}-${APP_ARCH}"
DIST_DIR="${OUTPUT_ROOT}/${RELEASE_ID}"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
APP_CONTENTS="${APP_BUNDLE}/Contents"
APP_MACOS_DIR="${APP_CONTENTS}/MacOS"
APP_RES_DIR="${APP_CONTENTS}/Resources"
APP_FW_DIR="${APP_CONTENTS}/Frameworks"

if [[ ${CLEAN} -eq 1 ]]; then
    rm -rf "${OUTPUT_ROOT}"
fi
rm -rf "${DIST_DIR}"
mkdir -p "${APP_MACOS_DIR}" "${APP_RES_DIR}" "${APP_FW_DIR}"

cp "${APP_EXECUTABLE}" "${APP_MACOS_DIR}/${APP_NAME}"
chmod 755 "${APP_MACOS_DIR}/${APP_NAME}"

if [[ -x "${CLI_EXECUTABLE}" ]]; then
    cp "${CLI_EXECUTABLE}" "${APP_MACOS_DIR}/rv"
    chmod 755 "${APP_MACOS_DIR}/rv"
fi

cat > "${APP_CONTENTS}/Info.plist" <<EOF
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
    <key>CFBundleIdentifier</key>
    <string>org.rhizovision.explorer</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

touch "${APP_CONTENTS}/PkgInfo"
printf "APPLRVE1" > "${APP_CONTENTS}/PkgInfo"

echo "Running macdeployqt: ${MACDEPLOYQT}"
DEPLOY_ARGS=(
    "${APP_BUNDLE}"
    "-always-overwrite"
    "-verbose=1"
    "-libpath=${INSTALL_PREFIX}/lib"
    "-libpath=${ENV_PREFIX}/lib"
)
if [[ -x "${APP_MACOS_DIR}/rv" ]]; then
    DEPLOY_ARGS+=("-executable=${APP_MACOS_DIR}/rv")
fi
"${MACDEPLOYQT}" "${DEPLOY_ARGS[@]}"

# Optional release docs in distribution folder.
if [[ -f "${RVE_DIR}/README.md" ]]; then
    cp "${RVE_DIR}/README.md" "${DIST_DIR}/README.md"
fi
if [[ -f "${RVE_DIR}/changelog.txt" ]]; then
    cp "${RVE_DIR}/changelog.txt" "${DIST_DIR}/CHANGELOG.txt"
fi

# Repro manifest: copy if available, otherwise generate a compact one.
if [[ -f "${INSTALL_PREFIX}/repro-manifest.txt" ]]; then
    cp "${INSTALL_PREFIX}/repro-manifest.txt" "${DIST_DIR}/repro-manifest.txt"
else
    OPENCV_VERSION="$("${CONDA_EXE}" list -p "${ENV_PREFIX}" | awk '$1=="opencv"{print $2; exit}')"
    QT_VERSION="$("${CONDA_EXE}" list -p "${ENV_PREFIX}" | awk '$1=="qt6-main"{print $2; exit}')"
    {
        echo "app_name=${APP_NAME}"
        echo "app_version=${APP_VERSION}"
        echo "arch=${APP_ARCH}"
        echo "opencv=${OPENCV_VERSION:-unknown}"
        echo "qt=${QT_VERSION:-unknown}"
        echo "install_prefix=${INSTALL_PREFIX}"
        echo "env_prefix=${ENV_PREFIX}"
    } > "${DIST_DIR}/repro-manifest.txt"
fi

# Verify no dependency still points to local build prefixes.
BAD_DEPS_REPORT="${DIST_DIR}/dependency_issues.txt"
rm -f "${BAD_DEPS_REPORT}"
while IFS= read -r binary; do
    if otool -L "${binary}" | tail -n +2 | awk '{print $1}' | rg -q "^${ENV_PREFIX}|^${INSTALL_PREFIX}"; then
        {
            echo "Unbundled dependency path found in: ${binary}"
            otool -L "${binary}"
            echo
        } >> "${BAD_DEPS_REPORT}"
    fi
done < <(find "${APP_BUNDLE}" -type f \( -perm -111 -o -name "*.dylib" \))

if [[ -f "${BAD_DEPS_REPORT}" ]]; then
    echo "Packaging failed dependency verification. See: ${BAD_DEPS_REPORT}" >&2
    exit 1
fi

# Drop macOS metadata sidecar files from release artifacts.
find "${DIST_DIR}" -name "._*" -delete
find "${DIST_DIR}" -name ".DS_Store" -delete

ZIP_PATH="${OUTPUT_ROOT}/${RELEASE_ID}.zip"
rm -f "${ZIP_PATH}"
(
    export COPYFILE_DISABLE=1
    cd "${OUTPUT_ROOT}"
    ditto -c -k --norsrc --keepParent "${RELEASE_ID}" "${ZIP_PATH}"
)

echo "Release package created:"
echo "  Distribution folder: ${DIST_DIR}"
echo "  App bundle: ${APP_BUNDLE}"
echo "  Zip: ${ZIP_PATH}"
