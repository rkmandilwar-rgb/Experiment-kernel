#!/bin/bash
# Static audit of the Stormbreaker root stack (KernelSU + SUSFS + NoMount).
# Run before spending CPU on a kernel build:  bash tools/root-integration/audit.sh [kernel_dir]
set -u

TOP=${1:-$(cd "$(dirname "$0")/../.." && pwd)}
cd "$TOP" || exit 1

FAIL=0
fail() { echo "  [FAIL] $*"; FAIL=1; }
ok()   { echo "  [ ok ] $*"; }

echo "== KernelSU driver"
for f in drivers/kernelsu/Kconfig drivers/kernelsu/Makefile drivers/kernelsu/ksu.c drivers/kernelsu/hook/setuid_hook.c; do
  [ -e "$f" ] && ok "$f present" || fail "$f missing"
done
grep -Eq 'obj-[$][(]CONFIG_KSU[)][[:space:]]+[+]= kernelsu/' drivers/Makefile && ok "drivers/Makefile wired" || fail "drivers/Makefile not wired"
grep -q "drivers/kernelsu/Kconfig" drivers/Kconfig && ok "drivers/Kconfig wired" || fail "drivers/Kconfig not wired"

echo "== SUSFS core"
for f in fs/susfs.c include/linux/susfs.h include/linux/susfs_def.h; do
  [ -e "$f" ] && ok "$f present" || fail "$f missing"
done
for sym in susfs_init susfs_start_sdcard_monitor_fn susfs_add_sus_path susfs_add_sus_kstat \
           susfs_set_uname susfs_set_cmdline_or_bootconfig susfs_add_open_redirect susfs_add_sus_map \
           susfs_get_enabled_features susfs_show_variant susfs_show_version; do
  grep -q "\b$sym\b" include/linux/susfs.h && ok "susfs.h: $sym" || fail "susfs.h: $sym not declared"
done

echo "== KernelSU <-> SUSFS glue"
grep -q "#include <linux/susfs.h>" drivers/kernelsu/ksu.c && ok "ksu.c includes susfs.h" || fail "ksu.c does not include susfs.h"
grep -q "susfs_init()" drivers/kernelsu/ksu.c && ok "ksu.c calls susfs_init()" || fail "ksu.c does not call susfs_init()"
grep -q "SUSFS_MAGIC" drivers/kernelsu/supercall/supercall.c && ok "supercall SUSFS magic dispatch" || fail "supercall SUSFS dispatch missing"
grep -q "susfs_start_sdcard_monitor_fn" drivers/kernelsu/supercall/dispatch.c && ok "dispatch boot-complete monitor" || fail "dispatch boot-complete monitor missing"
grep -q "ksu_module_mounted = true" drivers/kernelsu/runtime/boot_event.c && ok "module-mounted mark (boot_event)" || fail "module-mounted mark missing from runtime/boot_event.c"
grep -q "EVENT_POST_FS_DATA" drivers/kernelsu/supercall/dispatch.c && ok "dispatch boot-complete one-shot" || fail "dispatch boot-complete one-shot missing"
grep -q "susfs_is_current_ksu_domain" drivers/kernelsu/selinux/selinux.c && ok "selinux ksu-domain check" || fail "selinux ksu-domain check missing"
grep -q "susfs_extra_works" drivers/kernelsu/hook/setuid_hook.c && ok "setuid umount glue" || fail "setuid umount glue missing"

echo "== SUSFS hardening"
grep -q 'susfs_starts_with(iter->name, "is_zygote")' kernel/kallsyms.c \
  && ok "kallsyms hides the full KSU/SUSFS symbol set" || fail "kallsyms symbol filter incomplete"
grep -q 'susfs_ksu_sid' security/selinux/avc.c \
  && ok "AVC log spoofing targets KSU denials only" || fail "AVC log spoofing missing"
grep -q 'ksu_uid_should_umount' drivers/kernelsu/hook/setuid_hook.c \
  && ok "umount marking is profile-aware" || fail "umount marking not profile-aware"

# every extern the susfs core asks from the KSU driver must exist somewhere
echo "== cross-module symbols required by fs/susfs.c"
MISSING=""
while read -r sym; do
  [ -z "$sym" ] && continue
  if ! grep -rq "\b$sym\s*(" --include=*.c drivers/kernelsu; then
    MISSING="$MISSING $sym"
  fi
done <<< "$(grep -oE '^extern [^(]+\(([a-z_]+|susfs_[a-z_]+)\)' fs/susfs.c | sed -E 's/.*\b([a-zA-Z_]+)\(.*/\1/')"
while read -r sym; do
  [ -z "$sym" ] && continue
  grep -rq "\b$sym\b" --include=*.c drivers/kernelsu || MISSING="$MISSING $sym"
done <<< "$(grep -oE 'extern (u32|bool|struct cred \*) [a-z_]+' fs/susfs.c | sed -E 's/.* ([a-z_]+)$/\1/')"
if [ -n "$MISSING" ]; then
  fail "symbols used by fs/susfs.c not provided: $MISSING"
else
  ok "all ksu-side symbols referenced by fs/susfs.c are provided"
fi

echo "== kernel-side SUSFS hooks"
for site in "fs/namespace.c:susfs_is_current_ksu_domain" "fs/statfs.c:susfs_is_current_proc_umounted" \
            "fs/proc/fd.c:susfs_is_current_proc_umounted" "fs/proc/task_mmu.c:SUSFS_IS_INODE_SUS_MAP" \
            "kernel/kallsyms.c:susfs_" "kernel/sys.c:susfs_spoof_uname" \
            "mm/memory.c:SUSFS_IS_INODE_SUS_MAP" "security/selinux/avc.c:susfs_is_avc_log_spoofing_enabled" \
            "fs/readdir.c:susfs" "fs/namei.c:susfs" "fs/proc_namespace.c:susfs"; do
  file=${site%%:*}; sym=${site#*:}
  grep -q "$sym" "$file" && ok "$file: $sym" || fail "$file: $sym missing"
done

echo "== NoMount"
[ -e fs/nomount/nomount.c ] && ok "fs/nomount present" || fail "fs/nomount missing"
grep -q "obj-\$(CONFIG_NOMOUNT) += nomount/" fs/Makefile && ok "fs/Makefile wired" || fail "fs/Makefile not wired"
grep -q "fs/nomount/Kconfig" fs/Kconfig && ok "fs/Kconfig wired" || fail "fs/Kconfig not wired"

echo "== Haptics (aw8624 LRA driver)"
for f in drivers/misc/aw8624_haptic/aw8624.c drivers/misc/aw8624_haptic/aw8624.h; do
  [ -e "$f" ] && ok "$f present" || fail "$f missing"
done
grep -q "obj-\$(CONFIG_AW8624_HAPTIC) += aw8624_haptic/" drivers/misc/Makefile \
  && ok "drivers/misc/Makefile wired" || fail "drivers/misc/Makefile not wired"
grep -q "drivers/misc/aw8624_haptic/Kconfig" drivers/misc/Kconfig \
  && ok "drivers/misc/Kconfig wired" || fail "drivers/misc/Kconfig not wired"
# fixes carried by the imported driver revision
grep -q "aw8624->effect_id = data\[0\];" drivers/misc/aw8624_haptic/aw8624.c \
  && ok "effect id is propagated (consistent vibration)" || fail "effect-id propagation missing"
grep -q "aw8624_haptic_set_level" drivers/misc/aw8624_haptic/aw8624.c \
  && ok "ulevel gain scaling present" || fail "ulevel gain scaling missing"
grep -q "dev_attr_ulevel" drivers/misc/aw8624_haptic/aw8624.c \
  && ok "ulevel sysfs attribute registered" || fail "ulevel sysfs attribute missing"
grep -q 'input_dev->name = "aw8624_haptic";' drivers/misc/aw8624_haptic/aw8624.c \
  && ok "input device named aw8624_haptic" || fail "input device name unexpected"
grep -q "if (!aw8624->enable_pin_control)" drivers/misc/aw8624_haptic/aw8624.c \
  && ok "reset-gpio release guarded (probe/remove warning fix)" || fail "reset-gpio guard missing"
grep -q 'awinic,aw8624_haptic' arch/arm64/boot/dts/qcom/cust-atoll-idp.dtsi \
  && ok "device tree node present" || fail "aw8624 device tree node missing"

echo "== AnyKernel3 installer"
if bash "$TOP/tools/root-integration/test-ak3.sh" "$TOP/AnyKernel3" >/dev/null 2>&1; then
  ok "flashable zip installer resolves the boot partition"
else
  fail "AnyKernel3 installer check failed (run tools/root-integration/test-ak3.sh to see why)"
  bash "$TOP/tools/root-integration/test-ak3.sh" "$TOP/AnyKernel3" 2>&1 | sed 's/^/        /'
fi

echo "== config policy (defconfig + miatoll fragments)"
# accept either the make target (vendor/xiaomi/miatoll_defconfig) or a plain path
DEFCONFIG=${DEFCONFIG:-vendor/xiaomi/miatoll_defconfig}
[ -f "$DEFCONFIG" ] || DEFCONFIG="arch/arm64/configs/${DEFCONFIG}"
POLICY_SRC="$DEFCONFIG kernel/configs/miatoll/"*.config
for opt in CONFIG_KSU=y CONFIG_KSU_SUSFS=y CONFIG_NOMOUNT=y CONFIG_KALLSYMS_ALL=y \
           CONFIG_AW8624_HAPTIC=y \
           CONFIG_PID_NS=y CONFIG_IPC_NS=y CONFIG_USER_NS=y \
           CONFIG_SYSVIPC=y CONFIG_OVERLAY_FS=y; do
  grep -qxF "$opt" $POLICY_SRC && ok "$opt" || fail "$opt not enabled in defconfig/fragments"
done
# Kinesis-steal set must stay enabled
for opt in CONFIG_SCHED_CASS=y CONFIG_OPLUS_MM_HACKS=y CONFIG_PELT_UTIL_HALFLIFE_16=y \
           CONFIG_LLVM_POLLY=y CONFIG_LTO_CLANG=y CONFIG_INLINE_OPTIMIZATION=y \
           CONFIG_SHADOW_CALL_STACK=y CONFIG_CRYPTO_LZ4KD=y CONFIG_TCP_CONG_WESTWOOD=y; do
  grep -qxF "$opt" $POLICY_SRC && ok "$opt" || fail "$opt not enabled in defconfig/fragments"
done
# syscall-table tampering stays OFF (LSM/manual hooks only)
grep -qE '^CONFIG_KSU_TAMPER_SYSCALL_TABLE=[ym]' $POLICY_SRC \
  && fail "CONFIG_KSU_TAMPER_SYSCALL_TABLE must stay disabled" \
  || ok "CONFIG_KSU_TAMPER_SYSCALL_TABLE stays disabled"
# Simple LMK is the only low memory killer (4 GB anchor values)
for opt in CONFIG_ANDROID_SIMPLE_LMK=y CONFIG_ANDROID_SIMPLE_LMK_MINFREE=176 \
           CONFIG_ANDROID_SIMPLE_LMK_TIMEOUT_MSEC=100; do
  grep -qxF "$opt" $POLICY_SRC && ok "$opt" || fail "$opt not enabled in defconfig/fragments"
done
# BT/WiFi tuning policy
for opt in CONFIG_BT_HCIUART_QCA=y CONFIG_BT_HCIBTUSB_BCM=y CONFIG_BT_HCIBTUSB_RTL=y \
           CONFIG_CFG80211_INTERNAL_REGDB=y; do
  grep -qxF "$opt" $POLICY_SRC && ok "$opt" || fail "$opt not enabled in defconfig/fragments"
done
# Simple LMK dependencies must stay disabled
for opt in CONFIG_MEMCG CONFIG_PSI CONFIG_ANDROID_LOW_MEMORY_KILLER; do
  grep -qE "^${opt}=[ym]" $POLICY_SRC && fail "$opt must stay disabled (Simple LMK)" \
    || ok "$opt stays disabled"
done

echo
if [ "$FAIL" -ne 0 ]; then
  echo "AUDIT FAILED"
  exit 1
fi
echo "AUDIT PASSED"
