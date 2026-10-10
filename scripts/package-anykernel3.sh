#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# scripts/package-anykernel3.sh
# Package the AnyKernel3 flashable zip (Image.gz + dtb + dtbo).
# Run from the kernel source root after a successful build (out/ populated).
set -euo pipefail

TANGGAL=$(date +"%Y%m%d-%H")
RUN_NUM="${GITHUB_RUN_NUMBER:-local}"
AK3="AnyKernel3-stormbreaker"
rm -rf "$AK3" artifacts
mkdir -p artifacts

# Copy AnyKernel3 template, stripping placeholder/gitignore
rsync -a --exclude='.gitignore' --exclude='placeholder' AnyKernel3/ "$AK3/"

# Build products
cp out/arch/arm64/boot/Image.gz  "$AK3/"
cp out/arch/arm64/boot/dtbo.img  "$AK3/"
cp out/arch/arm64/boot/dtb.img   "$AK3/" 2>/dev/null || true

# Kernel modules (if any =m were built)
find out/ -name "*.ko" -exec cp {} "$AK3/modules/system/lib/modules/" \; 2>/dev/null || true

# Keep ramdisk/ and patch/ dirs present (even if empty)
mkdir -p "$AK3/ramdisk" "$AK3/patch"

# Get kernel release string
KREL=$(make -s O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 \
    CROSS_COMPILE=aarch64-linux-gnu- kernelrelease 2>/dev/null || echo "unknown")

# Package
ZIPFILE="Stormbreaker-miatoll-${TANGGAL}.zip"
(
  cd "$AK3"
  zip -r9 "../artifacts/${ZIPFILE}" . \
      -x '.git' -x 'README.md' -x '*placeholder'
)

# Raw images + metadata
cp out/arch/arm64/boot/Image.gz  artifacts/
cp out/arch/arm64/boot/dtbo.img  artifacts/
cp out/arch/arm64/boot/dtb.img   artifacts/ 2>/dev/null || true

# SHA256
(
  cd artifacts
  sha256sum Image.gz dtbo.img 2>/dev/null > SHA256SUMS || true
  sha256sum "$ZIPFILE"        >> SHA256SUMS || true
)

{
  echo "commit=${GITHUB_SHA:-HEAD}"
  echo "kernel.release=${KREL}"
  echo "zipfile=${ZIPFILE}"
  echo "date=${TANGGAL}"
  clang --version 2>/dev/null | head -1 || true
  ld.lld --version 2>/dev/null | head -1 || true
} > build-info.txt

echo ""
echo "========== Package complete =========="
ls -lh artifacts/