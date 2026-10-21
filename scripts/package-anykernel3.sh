#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# scripts/package-anykernel3.sh
# Package the AnyKernel3 flashable zip (kernel image only) and the raw
# image for the GitHub artifact.
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
#
# Only the kernel image is packaged.  AnyKernel3 falls back to the device
# tree already inside the boot image when the zip carries no dtb (and to the
# untouched dtbo partition when it carries no dtbo.img), which is exactly the
# policy anykernel.sh documents: replace the kernel, keep the vendor's
# hardware description.  Shipping a dtb here would override that and put
# boot and dtbo device trees from different builds on the same device.
cp out/arch/arm64/boot/Image.gz  "$AK3/"

if [ -s out/arch/arm64/boot/dtbo.img ] ||
   [ -s out/arch/arm64/boot/dts/qcom/cust-atoll-ab.dtb ]; then
  echo "NOTE: DTB/DTBO were built but are intentionally NOT packaged (kernel-only zip)."
fi

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

# Raw image + metadata (artifacts are for inspection, never flashed)
cp out/arch/arm64/boot/Image.gz  artifacts/

# SHA256
(
  cd artifacts
  sha256sum Image.gz > SHA256SUMS
  sha256sum "$ZIPFILE" >> SHA256SUMS
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
