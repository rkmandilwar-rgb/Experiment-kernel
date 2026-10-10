#!/usr/bin/env bash
# Stormbreaker kernel build for Xiaomi miatoll family (SM6125 "atoll"), Linux 4.14.
#
# Toolchain: Neutron Clang (LLVM) + ld.lld + llvm-binutils. GCC is NOT used:
#   - every compiler/linker is LLVM (CC/HOSTCC/LD/AR/NM/OBJCOPY/...),
#   - gcc/cc/g++ and aarch64-linux-gnu-* are shadowed by stubs that abort the build,
#     so a stray GCC invocation fails loudly instead of silently being used.
#
# Usage: ci/build.sh            (env overrides documented below)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# ---- configuration (override with environment variables) --------------------
NEUTRON_TAG="${NEUTRON_TAG:-30062026}"          # Neutron Clang build tag (see clang-build-catalogue)
TC_DIR="${TC_DIR:-$ROOT/.toolchain/neutron-clang}"
OUT="${OUT:-$ROOT/out}"
DIST="${DIST:-$ROOT/dist}"
JOBS="${JOBS:-$(nproc --all)}"
DEFCONFIG="${DEFCONFIG:-vendor/xiaomi/miatoll_defconfig}"
FRAGMENT_DIR="arch/arm64/configs/vendor/xiaomi/fragments"
KVER="$(make -s kernelversion 2>/dev/null || echo 4.14)"
STAMP="$(date -u +%Y%m%d-%H%M)"
ZIP_NAME="${ZIP_NAME:-Stormbreaker-miatoll-${KVER}-${STAMP}.zip}"

export ARCH=arm64 SUBARCH=arm64
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-stormbreaker}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-ci}"
export LC_ALL=C

# ---- 1. Neutron Clang toolchain (fetched + checksum verified) ---------------
fetch_neutron() {
  if [ -x "$TC_DIR/bin/clang" ]; then return; fi
  echo ">> Fetching Neutron Clang ${NEUTRON_TAG}"
  mkdir -p "$TC_DIR"
  local base="https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/${NEUTRON_TAG}"
  local tarball="$ROOT/.toolchain/neutron-clang-${NEUTRON_TAG}.tar.zst"
  curl -fsSL --retry 5 --retry-delay 5 -o "$tarball" "${base}/neutron-clang-${NEUTRON_TAG}.tar.zst"
  local info
  info="$(curl -fsSL "https://raw.githubusercontent.com/Neutron-Toolchains/clang-build-catalogue/main/${NEUTRON_TAG}-info.txt")"
  local want
  want="$(printf '%s\n' "$info" | awk '/^\[shasum\]/{getline; print $1}')"
  echo "${want}  ${tarball}" | sha256sum -c -
  zstd -dc "$tarball" | tar -xf - -C "$TC_DIR"
  rm -f "$tarball"
}

fetch_neutron
export PATH="$TC_DIR/bin:$PATH"

# ---- 2. Hard "no GCC" guard -------------------------------------------------
GUARD="$ROOT/.toolchain/nogcc-bin"
mkdir -p "$GUARD"
for bad in gcc cc g++ c++ aarch64-linux-gnu-gcc arm-linux-gnueabi-gcc aarch64-linux-android-gcc; do
  printf '#!/bin/sh\necho "ERROR: GCC (%s) is forbidden in this build; use Neutron clang" >&2\nexit 1\n' "$bad" > "$GUARD/$bad"
  chmod +x "$GUARD/$bad"
done
export PATH="$GUARD:$PATH"

command -v clang >/dev/null || { echo "clang missing from Neutron toolchain"; exit 1; }
clang --version | head -2
ld.lld --version | head -1

# Every tool the kernel makefiles may touch is LLVM. Host tools too.
export CC="clang"
export HOSTCC="clang" HOSTCXX="clang++"
export LD="ld.lld" HOSTLD="ld.lld"
export AR="llvm-ar" HOSTAR="llvm-ar"
export NM="llvm-nm" OBJCOPY="llvm-objcopy" OBJDUMP="llvm-objdump"
export READELF="llvm-readelf" STRIP="llvm-strip"
export CLANG_TRIPLE="aarch64-linux-gnu-"
export CROSS_COMPILE="aarch64-linux-gnu-"   # prefix only: clang's integrated assembler is used
export AS="clang"

if [ -n "${USE_CCACHE:-}" ] && command -v ccache >/dev/null; then
  export CC="ccache clang" HOSTCC="ccache clang"
  ccache -M "${CCACHE_MAXSIZE:-8G}" >/dev/null
fi

MAKE=(make -j"$JOBS" O="$OUT" ARCH=arm64 SUBARCH=arm64)
MAKE+=(CC="$CC" HOSTCC="$HOSTCC" HOSTCXX="$HOSTCXX" LD="$LD" HOSTLD="$HOSTLD"
       AR="$AR" HOSTAR="$HOSTAR" NM="$NM" OBJCOPY="$OBJCOPY" OBJDUMP="$OBJDUMP"
       READELF="$READELF" STRIP="$STRIP" CLANG_TRIPLE="$CLANG_TRIPLE"
       CROSS_COMPILE="$CROSS_COMPILE" AS="$AS")

# ---- 3. Configuration: defconfig + feature fragments ------------------------
rm -rf "$OUT"
mkdir -p "$OUT"
echo ">> Generating ${DEFCONFIG}"
"${MAKE[@]}" "$DEFCONFIG"

echo ">> Merging feature fragments"
FRAGMENTS=()
for f in "$FRAGMENT_DIR"/*.config; do FRAGMENTS+=("$f"); done
scripts/kconfig/merge_config.sh -m -O "$OUT" "$OUT/.config" "${FRAGMENTS[@]}"
"${MAKE[@]}" olddefconfig

# Sanity check: the features we promised are really on in the final .config
for sym in BPF_SYSCALL BPF_JIT CGROUP_BPF TCP_CONG_BBR DEFAULT_BBR EROFS_FS NTFS_RW \
           PID_NS USER_NS CGROUP_PIDS SYSVIPC MAC80211 HIDRAW USB_CONFIGFS_F_HID; do
  if ! grep -q "^CONFIG_${sym}=[ym]" "$OUT/.config"; then
    echo "ERROR: CONFIG_${sym} is not enabled in the final config"; exit 1
  fi
done
echo ">> Feature config verified"

# ---- 4. Build kernel, DTBs/DTBOs and modules --------------------------------
echo ">> Building Image.gz"
"${MAKE[@]}" Image.gz

echo ">> Building device trees and overlays"
"${MAKE[@]}" dtbs

echo ">> Building modules"
"${MAKE[@]}" modules

# ---- 5. Package the AnyKernel3 zip ------------------------------------------
PKG="$ROOT/.toolchain/package"
rm -rf "$PKG"
mkdir -p "$PKG" "$DIST"
cp -r "$ROOT/AnyKernel3/." "$PKG/"
rm -rf "$PKG/modules/system/lib/modules"/*
mkdir -p "$PKG/modules/system/lib/modules"

cp "$OUT/arch/arm64/boot/Image.gz" "$PKG/Image.gz"

DTS="$OUT/arch/arm64/boot/dts/qcom"
# Non-A/B atoll board DTBs (the A/B cust-atoll-ab base is intentionally excluded)
DTB_LIST="atoll-idp atoll-atp atoll-qrd atoll-wcd937x-idp atoll-usbc-idp atollp-idp atollp-atp atollp-qrd"
: > "$PKG/dtb"
for d in $DTB_LIST; do
  [ -f "$DTS/$d.dtb" ] || { echo "ERROR: missing $d.dtb"; exit 1; }
  cat "$DTS/$d.dtb" >> "$PKG/dtb"
done

# Overlays -> dtbo.img (flashed to the dtbo partition by AnyKernel3)
OVL_LIST="atoll-idp-overlay atoll-atp-overlay atoll-qrd-overlay atoll-wcd937x-idp-overlay atoll-usbc-idp-overlay atollp-idp-overlay atollp-atp-overlay atollp-qrd-overlay"
OVL_FILES=()
for o in $OVL_LIST; do
  [ -f "$DTS/$o.dtbo" ] || { echo "ERROR: missing $o.dtbo"; exit 1; }
  OVL_FILES+=("$DTS/$o.dtbo")
done
python3 "$ROOT/ci/tools/mkdtboimg.py" create "$PKG/dtbo.img" --page_size=4096 "${OVL_FILES[@]}"

# Modules (NetHunter Wi-Fi/BT/USB drivers etc.), stripped
find "$OUT" -name '*.ko' -print0 | while IFS= read -r -d '' ko; do
  llvm-strip --strip-debug -o "$PKG/modules/system/lib/modules/$(basename "$ko")" "$ko"
done

# Build the flashable zip
( cd "$PKG" && zip -qr9 "$DIST/$ZIP_NAME" . -x '.git*' )
echo ">> Created $DIST/$ZIP_NAME"
ls -la "$DIST/$ZIP_NAME"
sha256sum "$DIST/$ZIP_NAME" > "$DIST/$ZIP_NAME.sha256"
cp "$OUT/.config" "$DIST/config-${KVER}-miatoll"
