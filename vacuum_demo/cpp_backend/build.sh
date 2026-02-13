#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR_NAME="${1:-build_linux}"
BUILD_DIR="${SCRIPT_DIR}/${BUILD_DIR_NAME}"

# If a previous build directory was generated on Windows, its CMake cache will
# contain Windows-style paths and will fail on Linux. Nuke it and reconfigure.
if [[ -f "${BUILD_DIR}/CMakeCache.txt" ]]; then
	if grep -qE '([A-Za-z]:\\\\|[A-Za-z]:/)' "${BUILD_DIR}/CMakeCache.txt"; then
		echo "Detected non-Linux CMakeCache in ${BUILD_DIR_NAME}; removing it."
		rm -rf "${BUILD_DIR}"
	fi
fi

cmake -S "${SCRIPT_DIR}" -B "${BUILD_DIR}"
cmake --build "${BUILD_DIR}" --parallel "$(nproc)"

