#!/bin/bash
# Builds a single static, universal (arm64 + x86_64) `aria2c`.
#
# aria2 itself is small; its dependencies are the work. We build zlib, expat,
# c-ares and OpenSSL from source for each architecture, then aria2 against them,
# then lipo the two binaries together. Everything runs on the GitHub macOS
# runner, never on a user's machine.
#
# Output: $OUT_DIR/aria2c  (universal)
set -euo pipefail

OUT_DIR="${1:-$(pwd)/vendor}"
WORK="${WORK_DIR:-$(pwd)/build-aria2}"
ARIA2_VERSION="${ARIA2_VERSION:-1.37.0}"
OPENSSL_VERSION="${OPENSSL_VERSION:-3.3.2}"

ZLIB_VERSION=1.3.1
EXPAT_VERSION=2.6.3
CARES_VERSION=1.33.1

ARCHS=(arm64 x86_64)
mkdir -p "$OUT_DIR" "$WORK"

fetch() {
  local url="$1" dest="$2"
  if [[ ! -f "$dest" ]]; then
    echo "fetching $(basename "$dest")"
    curl -fsSL "$url" -o "$dest"
  fi
}

# --- sources ---------------------------------------------------------------
fetch "https://github.com/aria2/aria2/releases/download/release-${ARIA2_VERSION}/aria2-${ARIA2_VERSION}.tar.gz" "$WORK/aria2.tar.gz"
fetch "https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.gz" "$WORK/zlib.tar.gz"
fetch "https://github.com/libexpat/libexpat/releases/download/R_${EXPAT_VERSION//./_}/expat-${EXPAT_VERSION}.tar.gz" "$WORK/expat.tar.gz"
fetch "https://github.com/c-ares/c-ares/releases/download/v${CARES_VERSION}/c-ares-${CARES_VERSION}.tar.gz" "$WORK/cares.tar.gz"
fetch "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" "$WORK/openssl.tar.gz"

for arch in "${ARCHS[@]}"; do
  PREFIX="$WORK/prefix-$arch"
  BUILD="$WORK/build-$arch"
  rm -rf "$PREFIX" "$BUILD"
  mkdir -p "$PREFIX" "$BUILD"

  if [[ "$arch" == "x86_64" ]]; then
    export CFLAGS="-arch x86_64 -O2 -mmacosx-version-min=14.0"
    export CXXFLAGS="-arch x86_64 -O2 -mmacosx-version-min=14.0"
    export LDFLAGS="-arch x86_64 -mmacosx-version-min=14.0"
    HOST="x86_64-apple-darwin"
  else
    export CFLAGS="-arch arm64 -O2 -mmacosx-version-min=14.0"
    export CXXFLAGS="-arch arm64 -O2 -mmacosx-version-min=14.0"
    export LDFLAGS="-arch arm64 -mmacosx-version-min=14.0"
    HOST="arm-apple-darwin"
  fi

  echo "==== zlib ($arch) ===="
  tar xzf "$WORK/zlib.tar.gz" -C "$BUILD"
  ( cd "$BUILD/zlib-${ZLIB_VERSION}" && ./configure --static --prefix="$PREFIX" && make -j"$(sysctl -n hw.ncpu)" && make install )

  echo "==== expat ($arch) ===="
  tar xzf "$WORK/expat.tar.gz" -C "$BUILD"
  ( cd "$BUILD/expat-${EXPAT_VERSION}" && ./configure --disable-shared --enable-static --prefix="$PREFIX" && make -j"$(sysctl -n hw.ncpu)" && make install )

  echo "==== c-ares ($arch) ===="
  tar xzf "$WORK/cares.tar.gz" -C "$BUILD"
  ( cd "$BUILD/c-ares-${CARES_VERSION}" && ./configure --disable-shared --enable-static --prefix="$PREFIX" && make -j"$(sysctl -n hw.ncpu)" && make install )

  echo "==== openssl ($arch) ===="
  tar xzf "$WORK/openssl.tar.gz" -C "$BUILD"
  ( cd "$BUILD/openssl-${OPENSSL_VERSION}" && ./Configure "$HOST" no-shared no-tests --prefix="$PREFIX" && make -j"$(sysctl -n hw.ncpu)" && make install_sw )

  echo "==== aria2 ($arch) ===="
  tar xzf "$WORK/aria2.tar.gz" -C "$BUILD"
  ( cd "$BUILD/aria2-${ARIA2_VERSION}" && \
    ./configure \
      --prefix="$PREFIX" \
      --host="$HOST" \
      --disable-nls \
      --disable-ldap \
      --disable-bittorrent \
      --without-gnutls \
      --with-openssl \
      --with-libexpat \
      --with-libcares \
      --without-libxml2 \
      --without-sqlite3 \
      --enable-static \
      --disable-shared \
      ARIA2_STATIC=yes \
      PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" \
      CPPFLAGS="-I$PREFIX/include" \
      LDFLAGS="-L$PREFIX/lib -arch ${arch} -mmacosx-version-min=14.0" && \
    make -j"$(sysctl -n hw.ncpu)" )
  cp "$BUILD/aria2-${ARIA2_VERSION}/src/aria2c" "$WORK/aria2c-$arch"
done

echo "==== lipo ===="
lipo -create -output "$OUT_DIR/aria2c" "$WORK/aria2c-arm64" "$WORK/aria2c-x86_64"
chmod +x "$OUT_DIR/aria2c"
lipo -info "$OUT_DIR/aria2c"
"$OUT_DIR/aria2c" --version | head -1
echo "aria2c written to $OUT_DIR/aria2c"
