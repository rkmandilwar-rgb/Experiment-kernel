#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# scripts/package-anykernel3.sh
# Package the AnyKernel3 flashable zip (Image.gz + base DTB) and the raw
# images for the GitHub artifact.
#
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
# DTB - AnyKernel3 expects a file named "dtb" (no extension) and uses it as
# the base to merge the per-device overlays onto.  This is NOT optional: a zip
# without it would flash a boot image with no device tree at all, so a missing
# DTB is a hard error instead of a silent "|| true".
DTB_SRC="out/arch/arm64/boot/dts/qcom/cust-atoll-ab.dtb"
if [ ! -s "$DTB_SRC" ]; then
  echo "FATAL: $DTB_SRC is missing; refusing to build a DTB-less zip" >&2
  exit 1
fi
cp "$DTB_SRC" "$AK3/dtb"

# Kernel modules: NOT shipped, on purpose.
#   * AnyKernel3/anykernel.sh sets do.modules=0,
#   * the CI build never runs "make modules",
#   * the vendor defconfig has no "=m" left (see the module policy note there).
# So the zip stays kernel-only and flashing it never touches vendor/system.
if find out -name '*.ko' -print -quit | grep -q .; then
  echo "NOTE: .ko files were produced by the build; intentionally not packaged." >&2
fi

# Keep ramdisk/ and patch/ dirs present (even if empty)
mkdir -p "$AK3/ramdisk" "$AK3/patch"

# Get kernel release string
KREL=$(make -s O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 \
    CROSS_COMPILE=aarch64-linux-gnu- kernelrelease 2>/dev/null || echo "unknown")

# Package
ZIPFILE="Stormbreaker-miatoll-${TANGGAL}-build${RUN_NUM}.zip"
(
  cd "$AK3"
  zip -r9 "../artifacts/${ZIPFILE}" . \
      -x '.git' -x 'README.md' -x '*placeholder'
)

# Raw images + metadata
cp out/arch/arm64/boot/Image.gz  artifacts/
cp out/arch/arm64/boot/dtbo.img  artifacts/
cp "$DTB_SRC"                    artifacts/dtb

# SHA256
(
  cd artifacts
  sha256sum Image.gz dtbo.img dtb > SHA256SUMS
  sha256sum "$ZIPFILE"           >> SHA256SUMS
)

# Provenance: this belongs next to the uploaded artifacts, not in the repo
# root, otherwise it never reaches the download page.
{
  echo "commit=${GITHUB_SHA:-HEAD}"
  echo "kernel.release=${KREL}"
  echo "zipfile=${ZIPFILE}"
  echo "date=${TANGGAL}"
  clang --version 2>/dev/null | head -1 || true
  ld.lld --version 2>/dev/null | head -1 || true
} > artifacts/build-info.txt

echo ""
echo "========== Package complete =========="
ls -lh artifacts/
