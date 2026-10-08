#!/bin/bash
# Builds a single static, universal `mcdownloader-torrentd` (arm64 + x86_64).
#
# libtorrent drags in Boost and OpenSSL, so we let vcpkg resolve and build the
# dependencies per architecture, then lipo the two helper binaries together.
# We use vcpkg's stock `arm64-osx` / `x64-osx` triplets (static by default) and
# build release only, which halves the OpenSSL build and avoids the debug
# configuration entirely. Everything happens on the GitHub macOS runner;
# nothing is installed on a user's machine.
#
# Output: $OUT_DIR/mcdownloader-torrentd  (universal)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$REPO_ROOT/vendor}"
WORK="${WORK_DIR:-$REPO_ROOT/build-torrent}"
VCPKG_ROOT="${VCPKG_ROOT:-$WORK/vcpkg}"
VCPKG_REF="${VCPKG_REF:-2024.09.30}"
VERSION="${MCD_VERSION:-1.0.0}"

mkdir -p "$OUT_DIR" "$WORK"

if [[ ! -d "$VCPKG_ROOT" ]]; then
  git clone --depth 1 --branch "$VCPKG_REF" https://github.com/microsoft/vcpkg "$VCPKG_ROOT"
fi
"$VCPKG_ROOT"/bootstrap-vcpkg.sh -disableMetrics

# Release only: OpenSSL's debug build is slow and unnecessary for a shipped helper.
export VCPKG_BUILD_TYPE=release
export VCPKG_DISABLE_METRICS=1

build_arch() {
  local triplet="$1" arch="$2"
  echo "==== vcpkg dependencies ($triplet) ===="
  if ! "$VCPKG_ROOT/vcpkg" install "libtorrent:$triplet" \
        --triplet "$triplet" \
        --clean-after-build; then
    echo "==== vcpkg FAILED; dumping openssl build logs ===="
    for f in "$VCPKG_ROOT"/buildtrees/openssl/*-err.log "$VCPKG_ROOT"/buildtrees/openssl/*-out.log; do
      [[ -f "$f" ]] && { echo "----- $f -----"; tail -60 "$f"; }
    done
    echo "----- vcpkg issue body -----"
    [[ -f "$VCPKG_ROOT/installed/vcpkg/issue_body.md" ]] && cat "$VCPKG_ROOT/installed/vcpkg/issue_body.md"
    return 1
  fi

  local build_dir="$WORK/build-$arch"
  rm -rf "$build_dir"
  cmake -S "$REPO_ROOT/TorrentHelper" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DMCD_VERSION="$VERSION" \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
    -DVCPKG_TARGET_TRIPLET="$triplet"
  cmake --build "$build_dir" --config Release -j"$(sysctl -n hw.ncpu)"
  cp "$build_dir/mcdownloader-torrentd" "$WORK/torrentd-$arch"
}

build_arch arm64-osx arm64
build_arch x64-osx x86_64

echo "==== lipo ===="
lipo -create -output "$OUT_DIR/mcdownloader-torrentd" "$WORK/torrentd-arm64" "$WORK/torrentd-x86_64"
chmod +x "$OUT_DIR/mcdownloader-torrentd"
lipo -info "$OUT_DIR/mcdownloader-torrentd"
echo "helper written to $OUT_DIR/mcdownloader-torrentd"
