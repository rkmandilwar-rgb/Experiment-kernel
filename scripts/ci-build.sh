#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# ci-build.sh - CI build script for Stormbreaker (miatoll, non-GKI 4.14)
#
# Intended to run inside GitHub Actions on ubuntu-latest.
# Downloads Neutron Clang, merges the defconfig, builds the kernel, the
# DTBO image, and packages the AnyKernel3 zip.
#
# Environment:
#   ARCH          - default: arm64
#   NEUTRON_TAG   - Neutron Clang release tag, default: 06092026
#   KERNEL_NAME   - kernel version string baked into the zip filename,
#                   default: Stormbreaker-miatoll
#
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SRC"

export ARCH="${ARCH:-arm64}"
NEUTRON_TAG="${NEUTRON_TAG:-06092026}"
KERNEL_NAME="${KERNEL_NAME:-Stormbreaker-miatoll}"

TANGGAL=$(date +"%Y%m%d-%H")
JOBS=$(nproc)

# ---------- 0. Environment sanity -----------------------------------------
export KBUILD_BUILD_HOST="stormbreaker-ci"
export KBUILD_BUILD_USER="ci"
export LC_ALL=C
export USE_CCACHE=1

echo "==== Stormbreaker CI build ===="
echo "ARCH=$ARCH  JOBS=$JOBS  KERNEL_NAME=$KERNEL_NAME"
echo "DATE=$TANGGAL"

# ---------- 1. Neutron Clang -----------------------------------------------
CLANG_DIR="${PWD}/neutron-clang"
if [ ! -x "${CLANG_DIR}/bin/clang" ]; then
    echo "::group::Downloading Neutron Clang ${NEUTRON_TAG}"
    wget -q -O neutron-clang.tar.zst \
        "https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/${NEUTRON_TAG}/neutron-clang-${NEUTRON_TAG}.tar.zst"
    mkdir -p "$CLANG_DIR"
    zstd -d --stdout neutron-clang.tar.zst | tar xf - -C "$CLANG_DIR" --strip-components=1
    rm -f neutron-clang.tar.zst
    echo "::endgroup::"
fi
export PATH="${CLANG_DIR}/bin:${PATH}"
clang --version | head -2

# ---------- 2. GCC ARM32 (only used for the 32-bit vDSO) -------------------
if ! command -v arm-linux-gnueabi-gcc >/dev/null 2>&1; then
    echo "::group::Installing arm-linux-gnueabi-gcc"
    sudo apt-get update -qq
    sudo apt-get install -y -qq gcc-arm-linux-gnueabi >/dev/null
    echo "::endgroup::"
fi

# ---------- 3. Merge defconfig with feature fragments ----------------------
echo "::group::Merging defconfig"
scripts/merge-defconfig.sh \
    arch/arm64/configs/vendor/xiaomi/miatoll_defconfig
echo "::endgroup::"

# ---------- 4. Disable modversions (avoids clang-built CRC drift) ---------
scripts/config --file .config \
    -d CONFIG_MODVERSIONS

# ---------- 5. Build -------------------------------------------------------
echo "::group::Kernel build"
make -j"${JOBS}" \
    LLVM=1 \
    LLVM_IAS=1 \
    CC=clang \
    LD=ld.lld \
    AR=llvm-ar \
    NM=llvm-nm \
    OBJCOPY=llvm-objcopy \
    OBJDUMP=llvm-objdump \
    READELF=llvm-readelf \
    STRIP=llvm-strip \
    CLANG_TRIPLE=aarch64-linux-gnu- \
    CROSS_COMPILE= \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
    CONFIG_NO_ERROR_ON_MISMATCH=y \
    2>&1 | tee "${SRC}/build.log"
echo "::endgroup::"

# ---------- 6. Verify build products ---------------------------------------
BOOTDIR="arch/arm64/boot"
IMAGE="${BOOTDIR}/Image.gz"
DTBO="${BOOTDIR}/dtbo.img"

[ -f "$IMAGE" ] || { echo "FATAL: $IMAGE not found" >&2; exit 1; }
[ -f "$DTBO"  ] || { echo "FATAL: $DTBO not found" >&2;  exit 1; }
echo "Build products: $IMAGE $DTBO"

# ---------- 7. Package AnyKernel3 zip -------------------------------------
echo "::group::Packaging AnyKernel3 zip"
AK3_DIR="AnyKernel3-stormbreaker"
cp -r AnyKernel3 "$AK3_DIR"
cp "$IMAGE" "$AK3_DIR/"
cp "$DTBO"  "$AK3_DIR/"

# Include kernel modules if any were built as .ko
if find . -name "*.ko" -path "*/out/*" 2>/dev/null | head -1 | grep -q .; then
    find . -name "*.ko" -path "*/out/*" -exec cp {} "$AK3_DIR/modules/system/lib/modules/" \;
fi

cd "$AK3_DIR"
rm -f .gitignore
zip -r9 "../${KERNEL_NAME}-${TANGGAL}.zip" \
    * -x .git README.md '*placeholder'
cd ..
ls -lh "${KERNEL_NAME}-${TANGGAL}.zip"
echo "::endgroup::"

echo "Build complete: ${KERNEL_NAME}-${TANGGAL}.zip"