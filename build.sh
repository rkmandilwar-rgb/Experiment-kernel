#!/bin/bash
# Local build wrapper — produces the SAME kernel config and flashable ZIP
# as CI (.github/workflows/build.yml): merged fragments via
# scripts/merge-defconfig.sh + packaged by scripts/package-anykernel3.sh.
# (no `set -u`: sourcing user ~/.bashrc may reference unset variables)
set -eo pipefail

function compile()
{
source ~/.bashrc && source ~/.profile
export LC_ALL=C && export USE_CCACHE=1
ccache -M 25G
export ARCH=arm64
export KBUILD_BUILD_HOST=android-build
export KBUILD_BUILD_USER="kardebayan"
clangbin=clang/bin/clang
if ! [ -a "$clangbin" ]; then git clone --depth=1 https://github.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-6443078 clang
fi
gcc64bin=gcc64/bin/aarch64-linux-android-as
if ! [ -a "$gcc64bin" ]; then git clone --depth=1 https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9 gcc64
fi
gcc32bin=gcc32/bin/arm-linux-androideabi-as
if ! [ -a "$gcc32bin" ]; then git clone --depth=1 https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9 gcc32
fi

# ── Config: same recipe as CI ─────────────────────────────────────────
# miatoll_defconfig + feature fragments + 4 GB tuning policy
MERGED="arch/arm64/configs/vendor/xiaomi/stormbreaker_defconfig"
cp arch/arm64/configs/vendor/xiaomi/miatoll_defconfig "$MERGED"
scripts/merge-defconfig.sh "$MERGED"
make O=out ARCH=arm64 vendor/xiaomi/stormbreaker_defconfig
rm -f "$MERGED"
scripts/config --file out/.config -d CONFIG_MODVERSIONS
make O=out ARCH=arm64 olddefconfig

# ── Build ────────────────────────────────────────────────────────────
PATH="${PWD}/clang/bin:${PATH}:${PWD}/gcc32/bin:${PATH}:${PWD}/gcc64/bin:${PATH}" \
make -j$(nproc --all) O=out \
                      ARCH=arm64 \
                      CC="clang" \
                      CLANG_TRIPLE=aarch64-linux-gnu- \
                      CROSS_COMPILE="${PWD}/gcc64/bin/aarch64-linux-android-" \
                      CROSS_COMPILE_ARM32="${PWD}/gcc32/bin/arm-linux-androideabi-" \
                      LD=ld.lld \
                      CONFIG_NO_ERROR_ON_MISMATCH=y \
                      Image.gz
}

function zupload()
{
zimage=out/arch/arm64/boot/Image.gz
if ! [ -a "$zimage" ];
then
echo  " Failed To Compile Kernel"
else
echo -e " Kernel Compile Successful"
# Package the boot-only AnyKernel3 ZIP exactly like CI (no DTB/DTBO).
bash scripts/package-anykernel3.sh
fi
}
compile
zupload
