#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Package the boot-only AnyKernel3 ZIP (Image.gz; keep installed DTB/DTBO).
# Run from the kernel source root after a successful kernel-image build.
set -euo pipefail

TANGGAL=$(date +"%Y%m%d-%H")
RUN_NUM="${GITHUB_RUN_NUMBER:-local}"
AK3="AnyKernel3-stormbreaker"
rm -rf "$AK3" artifacts
mkdir -p artifacts

# Copy AnyKernel3 template, stripping placeholder/gitignore.
rsync -a --exclude='.gitignore' --exclude='placeholder' AnyKernel3/ "$AK3/"

# The image is standalone (appended-DTB config is off). No new DTB/DTBO is
# placed in this ZIP, so the installed device tree remains untouched.
cp out/arch/arm64/boot/Image.gz "$AK3/"

# Kernel modules (if any =m were built).
mkdir -p "$AK3/modules/system/lib/modules"
find out/ -name "*.ko" -exec cp {} "$AK3/modules/system/lib/modules/" \; 2>/dev/null || true

# Keep ramdisk/ and patch/ dirs present (even if empty).
mkdir -p "$AK3/ramdisk" "$AK3/patch"

# Get kernel release string.
KREL=$(make -s O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 \
    CROSS_COMPILE=aarch64-linux-gnu- kernelrelease 2>/dev/null || echo "unknown")

# Package the flashable ZIP.
ZIPFILE="Stormbreaker-miatoll-${TANGGAL}-build${RUN_NUM}.zip"
(
  cd "$AK3"
  zip -r9 "../artifacts/${ZIPFILE}" . \
      -x '.git' -x 'README.md' -x '*placeholder'
)

# Guard against accidentally reintroducing standalone DTB/DTBO files.
python3 - "artifacts/${ZIPFILE}" <<'PY'
from pathlib import PurePosixPath
from zipfile import ZipFile
import sys

archive = sys.argv[1]
with ZipFile(archive) as zf:
    names = zf.namelist()
    required = {"Image.gz", "anykernel.sh"}
    present = {PurePosixPath(name).name for name in names}
    missing = sorted(required - present)
    if missing:
        raise SystemExit(f"AnyKernel ZIP is missing required files: {missing}")
    forbidden = [
        name for name in names
        if PurePosixPath(name).name in {"dtb", "dtb.img", "dtbo.img"}
        or name.lower().endswith((".dtb", ".dtbo"))
    ]
    if forbidden:
        raise SystemExit(f"DTB/DTBO files must not be packaged: {forbidden}")
    print(f"verified ZIP contents: {len(names)} entries; no DTB/DTBO")
PY

# Uploadable build artifacts: kernel image, AnyKernel ZIP and their checksums.
cp out/arch/arm64/boot/Image.gz artifacts/
(
  cd artifacts
  sha256sum Image.gz "$ZIPFILE" > SHA256SUMS
)

{
  echo "commit=${GITHUB_SHA:-HEAD}"
  echo "kernel.release=${KREL}"
  echo "zipfile=${ZIPFILE}"
  echo "date=${TANGGAL}"
  echo "device_tree=preserved from currently installed ROM (no DTB/DTBO included)"
  clang --version 2>/dev/null | head -1 || true
  ld.lld --version 2>/dev/null | head -1 || true
} > build-info.txt

echo ""
echo "========== Package complete =========="
ls -lh artifacts/
