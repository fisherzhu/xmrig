#!/usr/bin/env bash
set -Eeuo pipefail

# Build a CPU-only, statically linked Linux x86_64 release candidate.
# Prerequisites: GCC/G++, make, Perl, CMake >= 3.10, wget, tar, sha256sum,
# file, readelf, and the usual libc development headers. No system package
# installation or GitHub publication is performed by this script.
# Use JOBS=2 (the default) and run under nice/taskset on a shared build host.

readonly REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly CMAKE_BIN="${CMAKE_BIN:-cmake}"
readonly JOBS="${JOBS:-2}"
readonly BUILD_ROOT="${BUILD_ROOT:-${REPO_DIR}/build/static-linux-x86_64}"
readonly RELEASE_ID="${RELEASE_ID:-dev-$(git -C "$REPO_DIR" rev-parse --short=12 HEAD)}"

readonly UV_VERSION=1.51.0
readonly UV_SHA256=5f0557b90b1106de71951a3c3931de5e0430d78da1d9a10287ebc7a3f78ef8eb
readonly SSL_VERSION=3.0.22
readonly SSL_SHA256=67ebca7e50d17383028045486653492195b83db95f8558709701bb47b5c1ef81
readonly HWLOC_VERSION=2.12.1
readonly HWLOC_SHA256=ffa02c3a308275a9339fbe92add054fac8e9a00cb8fe8c53340094012cb7c633

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
require() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || die 'Linux x86_64 is required'
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die 'JOBS must be a positive integer'
[[ "$RELEASE_ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die 'Invalid RELEASE_ID'
for command_name in git wget tar sha256sum make perl file readelf install cc c++; do require "$command_name"; done
require "$CMAKE_BIN"
git -C "$REPO_DIR" merge-base --is-ancestor v6.26.0 HEAD || die 'Source must descend from v6.26.0'
[[ -z "$(git -C "$REPO_DIR" status --porcelain)" ]] || die 'Refusing to build from a dirty source tree'

mkdir -p -- "$BUILD_ROOT"/{downloads,sources,build,dist}
readonly WORK_DIR="$(cd -- "$BUILD_ROOT" && pwd -P)"
readonly DEPS_DIR="$WORK_DIR/deps/uv${UV_VERSION}-ssl${SSL_VERSION}-hwloc${HWLOC_VERSION}"
readonly APP_BUILD="$WORK_DIR/build/app-uv${UV_VERSION}-ssl${SSL_VERSION}-hwloc${HWLOC_VERSION}"
mkdir -p -- "$DEPS_DIR"

verify_archive() {
    printf '%s  %s\n' "$2" "$1" | sha256sum --check --status - || die "SHA-256 mismatch: $1"
}

download_archive() {
    local archive="$WORK_DIR/downloads/$1"
    if [[ ! -f "$archive" ]]; then
        wget --https-only --tries=3 --timeout=30 -q -O "$archive.part" "$2" || die "Download failed: $2"
        verify_archive "$archive.part" "$3"
        mv -- "$archive.part" "$archive"
    fi
    verify_archive "$archive" "$3"
}

extract_archive() {
    local name="$1"
    local source_dir="$WORK_DIR/sources/$name"
    if [[ ! -f "$source_dir/.archive-verified" ]]; then
        [[ ! -e "$source_dir" ]] || die "Incomplete extraction at $source_dir; inspect it before retrying"
        tar -xzf "$WORK_DIR/downloads/$name.tar.gz" -C "$WORK_DIR/sources"
        touch "$source_dir/.archive-verified"
    fi
}

download_archive "libuv-v${UV_VERSION}.tar.gz" \
    "https://dist.libuv.org/dist/v${UV_VERSION}/libuv-v${UV_VERSION}.tar.gz" "$UV_SHA256"
download_archive "openssl-${SSL_VERSION}.tar.gz" \
    "https://github.com/openssl/openssl/releases/download/openssl-${SSL_VERSION}/openssl-${SSL_VERSION}.tar.gz" "$SSL_SHA256"
download_archive "hwloc-${HWLOC_VERSION}.tar.gz" \
    "https://download.open-mpi.org/release/hwloc/v2.12/hwloc-${HWLOC_VERSION}.tar.gz" "$HWLOC_SHA256"
extract_archive "libuv-v${UV_VERSION}"
extract_archive "openssl-${SSL_VERSION}"
extract_archive "hwloc-${HWLOC_VERSION}"

if [[ ! -f "$DEPS_DIR/.libuv-ready" ]]; then
    "$CMAKE_BIN" -S "$WORK_DIR/sources/libuv-v${UV_VERSION}" -B "$WORK_DIR/build/libuv-${UV_VERSION}" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$DEPS_DIR" -DCMAKE_INSTALL_LIBDIR=lib \
        -DLIBUV_BUILD_SHARED=OFF -DLIBUV_BUILD_TESTS=OFF -DBUILD_TESTING=OFF
    "$CMAKE_BIN" --build "$WORK_DIR/build/libuv-${UV_VERSION}" --parallel "$JOBS"
    "$CMAKE_BIN" --install "$WORK_DIR/build/libuv-${UV_VERSION}"
    [[ -f "$DEPS_DIR/lib/libuv.a" ]] || die 'libuv.a was not installed'
    touch "$DEPS_DIR/.libuv-ready"
fi

if [[ ! -f "$DEPS_DIR/.openssl-ready" ]]; then
    (
        cd -- "$WORK_DIR/sources/openssl-${SSL_VERSION}"
        ./config no-shared no-asm no-zlib no-comp no-dgram no-filenames no-cms \
            --prefix="$DEPS_DIR" --openssldir="$DEPS_DIR/ssl" --libdir=lib
        make -j "$JOBS"
        make install_sw
    )
    [[ -f "$DEPS_DIR/lib/libssl.a" && -f "$DEPS_DIR/lib/libcrypto.a" ]] || die 'OpenSSL static libraries were not installed'
    touch "$DEPS_DIR/.openssl-ready"
fi

if [[ ! -f "$DEPS_DIR/.hwloc-ready" ]]; then
    (
        cd -- "$WORK_DIR/sources/hwloc-${HWLOC_VERSION}"
        ./configure --prefix="$DEPS_DIR" --libdir="$DEPS_DIR/lib" \
            --disable-shared --enable-static --disable-io --disable-libudev --disable-libxml2
        make -j "$JOBS"
        make install
    )
    [[ -f "$DEPS_DIR/lib/libhwloc.a" ]] || die 'hwloc.a was not installed'
    touch "$DEPS_DIR/.hwloc-ready"
fi

"$CMAKE_BIN" -S "$REPO_DIR" -B "$APP_BUILD" \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_STATIC=ON -DXMRIG_DEPS="$DEPS_DIR" \
    -DWITH_OPENCL=OFF -DWITH_CUDA=OFF -DWITH_HWLOC=ON -DWITH_TLS=ON \
    -DWITH_RANDOMX=ON -DWITH_EMBEDDED_CONFIG=OFF \
    -DUV_INCLUDE_DIR="$DEPS_DIR/include" -DUV_LIBRARY="$DEPS_DIR/lib/libuv.a" \
    -DHWLOC_INCLUDE_DIR="$DEPS_DIR/include" -DHWLOC_LIBRARY="$DEPS_DIR/lib/libhwloc.a" \
    -DOPENSSL_INCLUDE_DIR="$DEPS_DIR/include" \
    -DOPENSSL_SSL_LIBRARY="$DEPS_DIR/lib/libssl.a" \
    -DOPENSSL_CRYPTO_LIBRARY="$DEPS_DIR/lib/libcrypto.a"
"$CMAKE_BIN" --build "$APP_BUILD" --parallel "$JOBS"

readonly BIN="$APP_BUILD/xmrig"
[[ -x "$BIN" ]] || die 'XMRig binary was not built'
file "$BIN" | grep -q 'statically linked' || die 'XMRig binary is not static'
if readelf -l "$BIN" | grep -q INTERP; then die 'XMRig binary has a dynamic interpreter'; fi
"$BIN" --version | grep -q 'XMRig 6.26.0' || die 'Unexpected XMRig version'

readonly PACKAGE="xmrig-${RELEASE_ID}-linux-x86_64-static-cpu"
readonly ARCHIVE="$WORK_DIR/dist/$PACKAGE.tar.gz"
[[ ! -e "$ARCHIVE" ]] || die "Archive already exists: $ARCHIVE"
readonly STAGE="$(mktemp -d "$WORK_DIR/stage.XXXXXX")"
install -d -- "$STAGE/$PACKAGE"
install -m 755 -- "$BIN" "$STAGE/$PACKAGE/xmrig"
install -m 644 -- "$REPO_DIR/LICENSE" "$STAGE/$PACKAGE/LICENSE"
printf 'Source: https://github.com/fisherzhu/xmrig\nCommit: %s\nBase: v6.26.0\nBuild: Linux x86_64 static CPU-only\nDependencies: libuv %s, OpenSSL %s, hwloc %s\nBinary SHA-256: %s\nNote: static glibc may still require matching runtime NSS/DNS components.\n' \
    "$(git -C "$REPO_DIR" rev-parse HEAD)" "$UV_VERSION" "$SSL_VERSION" "$HWLOC_VERSION" \
    "$(sha256sum "$BIN" | cut -d ' ' -f 1)" > "$STAGE/$PACKAGE/BUILDINFO.txt"
tar -C "$STAGE" -czf "$ARCHIVE" "$PACKAGE"
(cd -- "$WORK_DIR/dist" && sha256sum "$PACKAGE.tar.gz" > "$PACKAGE.tar.gz.sha256")
printf 'Built %s\n' "$ARCHIVE"
