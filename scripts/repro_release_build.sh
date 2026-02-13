#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RVE_SRC_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CVUTIL_SRC_DEFAULT="$(cd "${RVE_SRC_DIR}/../cvutil" && pwd)"
ENV_FILE="${SCRIPT_DIR}/repro-conda-env.yml"

CONDA_EXE="${CONDA_EXE:-conda}"
ENV_PREFIX="${ENV_PREFIX:-${HOME}/.conda/envs/rhizovision-repro}"
INSTALL_PREFIX="${INSTALL_PREFIX:-${RVE_SRC_DIR}/../_install/repro}"
BUILD_ROOT="${BUILD_ROOT:-${RVE_SRC_DIR}/build/repro}"
GENERATOR="${GENERATOR:-Ninja}"
CVUTIL_SRC="${CVUTIL_SRC:-${CVUTIL_SRC_DEFAULT}}"
RVE_SRC="${RVE_SRC:-${RVE_SRC_DIR}}"
MAC_ARCH="${MAC_ARCH:-}"

CREATE_ENV=1
CLEAN=0
HOST_OS="$(uname -s)"
HOST_ARCH="$(uname -m)"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Builds cvutil and RhizoVisionExplorer with a pinned dependency stack and fixed CMake flags.

Options:
  --skip-env-create       Do not create/update conda environment
  --clean                 Remove build and install directories before building
  --env-prefix PATH       Conda environment prefix (default: ${ENV_PREFIX})
  --install-prefix PATH   Install prefix (default: ${INSTALL_PREFIX})
  --build-root PATH       Build root (default: ${BUILD_ROOT})
  --generator NAME        CMake generator (default: ${GENERATOR})
  --cvutil-src PATH       cvutil source path (default: ${CVUTIL_SRC_DEFAULT})
  --rve-src PATH          RhizoVisionExplorer source path (default: ${RVE_SRC_DIR})
  --mac-arch ARCH         macOS target architecture: x86_64 or arm64
  -h, --help              Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-env-create) CREATE_ENV=0 ;;
        --clean) CLEAN=1 ;;
        --env-prefix) ENV_PREFIX="$2"; shift ;;
        --install-prefix) INSTALL_PREFIX="$2"; shift ;;
        --build-root) BUILD_ROOT="$2"; shift ;;
        --generator) GENERATOR="$2"; shift ;;
        --cvutil-src) CVUTIL_SRC="$2"; shift ;;
        --rve-src) RVE_SRC="$2"; shift ;;
        --mac-arch) MAC_ARCH="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
    shift
done

CONDA_SUBDIR_OVERRIDE=""
if [[ "${HOST_OS}" == "Darwin" ]]; then
    if [[ -z "${MAC_ARCH}" ]]; then
        # Strict reproducibility mode: align with Windows/Linux x86_64 behavior.
        MAC_ARCH="x86_64"
    fi

    case "${MAC_ARCH}" in
        x86_64)
            CONDA_SUBDIR_OVERRIDE="osx-64"
            ;;
        arm64)
            CONDA_SUBDIR_OVERRIDE="osx-arm64"
            ;;
        *)
            echo "Invalid --mac-arch value: ${MAC_ARCH}. Expected x86_64 or arm64." >&2
            exit 1
            ;;
    esac
fi

if [[ ! -d "${CVUTIL_SRC}" ]]; then
    echo "cvutil source path not found: ${CVUTIL_SRC}" >&2
    exit 1
fi

if [[ ! -d "${RVE_SRC}" ]]; then
    echo "RhizoVisionExplorer source path not found: ${RVE_SRC}" >&2
    exit 1
fi

if [[ ${CLEAN} -eq 1 ]]; then
    rm -rf "${BUILD_ROOT}" "${INSTALL_PREFIX}"
fi

mkdir -p "${BUILD_ROOT}" "${INSTALL_PREFIX}"

if [[ ${CREATE_ENV} -eq 1 ]]; then
    if [[ -n "${CONDA_SUBDIR_OVERRIDE}" ]]; then
        CONDA_SUBDIR="${CONDA_SUBDIR_OVERRIDE}" "${CONDA_EXE}" env update --prune -p "${ENV_PREFIX}" -f "${ENV_FILE}"
    else
        "${CONDA_EXE}" env update --prune -p "${ENV_PREFIX}" -f "${ENV_FILE}"
    fi
fi

conda_run() {
    "${CONDA_EXE}" run -p "${ENV_PREFIX}" "$@"
}

CVUTIL_BUILD_DIR="${BUILD_ROOT}/cvutil"
RVE_BUILD_DIR="${BUILD_ROOT}/rhizovisionexplorer"

COMMON_RELEASE_FLAGS=(
    "-G" "${GENERATOR}"
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_CXX_STANDARD=17"
    "-DCMAKE_CXX_STANDARD_REQUIRED=ON"
    "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
    "-DENABLE_AVX512=OFF"
    "-DENABLE_AVX2_FMA=ON"
)

if [[ "${HOST_OS}" == "Darwin" ]]; then
    COMMON_RELEASE_FLAGS+=("-DCMAKE_OSX_ARCHITECTURES=${MAC_ARCH}")
fi

echo "Configuring cvutil ..."
conda_run cmake -S "${CVUTIL_SRC}" -B "${CVUTIL_BUILD_DIR}" \
    "${COMMON_RELEASE_FLAGS[@]}" \
    "-DCMAKE_PREFIX_PATH=${ENV_PREFIX}" \
    "-DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX}" \
    "-DCVUTIL_EXPECTED_OPENCV_MAJOR_MINOR=4.11" \
    "-DCVUTIL_EXPECTED_QT_MAJOR_MINOR=6.9" \
    "-DCVUTIL_ENFORCE_DEPENDENCY_MAJOR_MINOR=ON" \
    "-DUSE_MIMALLOC=ON"

echo "Building cvutil ..."
conda_run cmake --build "${CVUTIL_BUILD_DIR}" --parallel
conda_run cmake --install "${CVUTIL_BUILD_DIR}" --prefix "${INSTALL_PREFIX}"

echo "Configuring RhizoVisionExplorer ..."
conda_run cmake -S "${RVE_SRC}" -B "${RVE_BUILD_DIR}" \
    "${COMMON_RELEASE_FLAGS[@]}" \
    "-DCMAKE_PREFIX_PATH=${INSTALL_PREFIX};${ENV_PREFIX}" \
    "-DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX}" \
    "-Dcvutil_DIR=${INSTALL_PREFIX}/lib/cmake/cvutil" \
    "-DRHIZO_EXPECTED_OPENCV_MAJOR_MINOR=4.11" \
    "-DRHIZO_EXPECTED_QT_MAJOR_MINOR=6.9" \
    "-DRHIZO_ENFORCE_DEPENDENCY_MAJOR_MINOR=ON"

echo "Building RhizoVisionExplorer ..."
conda_run cmake --build "${RVE_BUILD_DIR}" --parallel
conda_run cmake --install "${RVE_BUILD_DIR}" --prefix "${INSTALL_PREFIX}"

OPENCV_VERSION="$("${CONDA_EXE}" list -p "${ENV_PREFIX}" | awk '$1=="opencv"{print $2; exit}')"
QT_VERSION="$("${CONDA_EXE}" list -p "${ENV_PREFIX}" | awk '$1=="qt6-main"{print $2; exit}')"

case "${OPENCV_VERSION}" in
    4.11.*) ;;
    *) echo "OpenCV version mismatch: expected 4.11.x, got ${OPENCV_VERSION}" >&2; exit 1 ;;
esac

case "${QT_VERSION}" in
    6.9.*) ;;
    *) echo "Qt version mismatch: expected 6.9.x, got ${QT_VERSION}" >&2; exit 1 ;;
esac

MANIFEST="${INSTALL_PREFIX}/repro-manifest.txt"
{
    echo "opencv=${OPENCV_VERSION}"
    echo "qt=${QT_VERSION}"
    echo "generator=${GENERATOR}"
    echo "build_type=Release"
    echo "cxx_standard=17"
    echo "enable_avx512=OFF"
    echo "enable_avx2_fma=ON"
    echo "cvutil_expected_opencv=4.11"
    echo "cvutil_expected_qt=6.9"
    echo "rhizo_expected_opencv=4.11"
    echo "rhizo_expected_qt=6.9"
    if [[ "${HOST_OS}" == "Darwin" ]]; then
        echo "mac_arch=${MAC_ARCH}"
        echo "conda_subdir=${CONDA_SUBDIR_OVERRIDE}"
    fi
} > "${MANIFEST}"

echo "Reproducible build complete."
echo "Install prefix: ${INSTALL_PREFIX}"
echo "Manifest: ${MANIFEST}"
if [[ "${HOST_OS}" == "Darwin" && "${MAC_ARCH}" == "x86_64" && "${HOST_ARCH}" == "arm64" ]]; then
    echo "Note: Built x86_64 binaries for strict parity. Run on Apple Silicon with Rosetta."
fi
