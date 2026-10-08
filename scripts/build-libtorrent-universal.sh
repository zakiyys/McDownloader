#!/bin/bash
# Builds a single static, universal `mcdownloader-torrentd` (arm64 + x86_64).
#
# libtorrent drags in Boost and OpenSSL, so we let vcpkg resolve and build the
# dependencies per architecture, then lipo the two helper binaries together.
# Everything happens on the GitHub macOS runner; nothing is installed on a
# user's machine.
#
# Output: $OUT_DIR/mcdownloader-torrentd  (universal)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$REPO_ROOT/vendor}"
WORK="${WORK_DIR:-$REPO_ROOT/build-torrent}"
VCPKG_ROOT="${VCPKG_ROOT:-$WORK/vcpkg}"
VCPKG_REF="${VCPKG_REF:-2024.09.30}"
VERSION="${MCD_VERSION:-1.0.0}"

TOOLCHAIN=""
mkdir -p "$OUT_DIR" "$WORK"

if [[ ! -d "$VCPKG_ROOT" ]]; then
  git clone --depth 1 --branch "$VCPKG_REF" https://github.com/microsoft/vcpkg "$VCPKG_ROOT"
fi
"$VCPKG_ROOT"/bootstrap-vcpkg.sh -disableMetrics
TOOLCHAIN="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake"

build_arch() {
  local triplet="$1" arch="$2"
  echo "==== vcpkg dependencies ($triplet) ===="
  "$VCPKG_ROOT/vcpkg" install "libtorrent:$triplet" \
    --clean-after-build --x-feature=core

  local build_dir="$WORK/build-$arch"
  rm -rf "$build_dir"
  cmake -S "$REPO_ROOT/TorrentHelper" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DMCD_VERSION="$VERSION" \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DVCPKG_TARGET_TRIPLET="$triplet" \
    -DVCPKG_OVERLAY_TRIPLETS="$REPO_ROOT/ci/triplets"
  cmake --build "$build_dir" --config Release -j"$(sysctl -n hw.ncpu)"
  cp "$build_dir/mcdownloader-torrentd" "$WORK/torrentd-$arch"
}

build_arch arm64-osx-static arm64
build_arch x64-osx-static x86_64

echo "==== lipo ===="
lipo -create -output "$OUT_DIR/mcdownloader-torrentd" "$WORK/torrentd-arm64" "$WORK/torrentd-x86_64"
chmod +x "$OUT_DIR/mcdownloader-torrentd"
lipo -info "$OUT_DIR/mcdownloader-torrentd"
echo "helper written to $OUT_DIR/mcdownloader-torrentd"
