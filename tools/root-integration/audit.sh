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
grep -q "ksu_module_mounted" drivers/kernelsu/supercall/dispatch.c && ok "dispatch module-mounted mark" || fail "dispatch module-mounted mark missing"
grep -q "EVENT_POST_FS_DATA" drivers/kernelsu/supercall/dispatch.c && ok "dispatch boot-complete one-shot" || fail "dispatch boot-complete one-shot missing"
grep -q "susfs_is_current_ksu_domain" drivers/kernelsu/selinux/selinux.c && ok "selinux ksu-domain check" || fail "selinux ksu-domain check missing"
grep -q "susfs_extra_works" drivers/kernelsu/hook/setuid_hook.c && ok "setuid umount glue" || fail "setuid umount glue missing"

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

echo "== SEA ports (Reflex / Simple GPU / BT + wakelock tuning / KFENCE / NandSwap)"
grep -q "CPU_FREQ_GOV_REFLEX" drivers/cpufreq/Kconfig \
  && ok "Reflex Kconfig wired" || fail "Reflex Kconfig missing"
grep -qE 'obj-[$][(]CONFIG_CPU_FREQ_GOV_REFLEX[)]' drivers/cpufreq/Makefile \
  && grep -qF 'cpufreq_reflex.o' drivers/cpufreq/Makefile \
  && ok "Reflex Makefile wired" || fail "Reflex Makefile not wired"
[ -e drivers/cpufreq/cpufreq_reflex.c ] && ok "cpufreq_reflex.c present" || fail "cpufreq_reflex.c missing"
grep -q "CONFIG_CPU_FREQ_GOV_REFLEX=y" arch/arm64/configs/vendor/xiaomi/miatoll_defconfig \
  && ok "Reflex enabled in defconfig" || fail "Reflex not enabled in defconfig"
grep -q "simple_gpu_algorithm" drivers/devfreq/governor_msm_adreno_tz.c \
  && ok "Simple GPU hook in msm_adreno_tz" || fail "Simple GPU hook missing"
grep -qF 'simple_gpu_algorithm.o' drivers/devfreq/Makefile \
  && ok "Simple GPU built alongside adreno tz" || fail "Simple GPU missing from devfreq Makefile"
for opt in CONFIG_BT_RFCOMM=y CONFIG_BT_RFCOMM_TTY=y CONFIG_BT_BNEP=y CONFIG_BT_HIDP=y \
           CONFIG_PM_AUTOSLEEP=y CONFIG_PM_WAKELOCKS_GC=y; do
  grep -q "$opt" arch/arm64/configs/vendor/xiaomi/miatoll_defconfig \
    && ok "defconfig: $opt" || fail "defconfig lost $opt"
done
[ -e mm/kfence/core.c ] && ok "kfence core present" || fail "kfence core missing"
[ -e include/linux/kfence.h ] && ok "kfence public header present" || fail "kfence header missing"
grep -qE 'obj-[$][(]CONFIG_KFENCE[)]' mm/Makefile \
  && ok "KFENCE wired into mm/Makefile" || fail "KFENCE not in mm/Makefile"
grep -qF 'lib/Kconfig.kfence' lib/Kconfig.debug \
  && ok "KFENCE Kconfig sourced" || fail "lib/Kconfig.kfence not sourced"
grep -q "kfence_handle_page_fault" arch/arm64/mm/fault.c \
  && ok "arm64 fault hook present" || fail "arm64 fault hook missing"
grep -q "kfence_alloc" mm/slub.c \
  && ok "SLUB alloc hook present" || fail "SLUB alloc hook missing"
grep -q "kfence_free" mm/slub.c \
  && ok "SLUB free hook present" || fail "SLUB free hook missing"
grep -q "select HAVE_ARCH_KFENCE" arch/arm64/Kconfig \
  && ok "arm64 selects HAVE_ARCH_KFENCE" || fail "HAVE_ARCH_KFENCE not selected"
grep -q "kfence_alloc_pool" init/main.c && grep -q "kfence_init" init/main.c \
  && ok "KFENCE boot init wired" || fail "KFENCE boot init missing"
for opt in CONFIG_KFENCE=y CONFIG_KFENCE_STATIC_KEYS=y CONFIG_KFENCE_SAMPLE_INTERVAL=100 \
           CONFIG_KFENCE_NUM_OBJECTS=255; do
  grep -q "$opt" arch/arm64/configs/vendor/xiaomi/miatoll_defconfig \
    && ok "defconfig: $opt" || fail "defconfig lost $opt"
done
[ -e drivers/soc/oplus_nandswap/nandswap_core.c ] && ok "nandswap core present" || fail "nandswap core missing"
[ -e include/linux/nandswap.h ] && ok "nandswap header present" || fail "nandswap header missing"
grep -qE 'obj-[$][(]CONFIG_NANDSWAP[)]' drivers/soc/Makefile \
  && ok "NandSwap wired into drivers/soc" || fail "NandSwap not in drivers/soc/Makefile"
grep -q "oplus_nandswap/Kconfig" drivers/soc/Kconfig \
  && ok "NandSwap Kconfig sourced" || fail "NandSwap Kconfig not sourced"
grep -q "SWP_NANDSWAP" include/linux/swap.h \
  && ok "swap.h SWP_NANDSWAP flag" || fail "swap.h missing SWP_NANDSWAP"
grep -q "SWAP_NANDSWAP_PRIO" include/linux/swap.h \
  && ok "swap.h SWAP_NANDSWAP_PRIO" || fail "swap.h missing SWAP_NANDSWAP_PRIO"
grep -q "nswap_reclaim_page_list" mm/vmscan.c \
  && ok "vmscan nswap_reclaim_page_list" || fail "vmscan nswap hook missing"
grep -q "current_is_nswapoutd" mm/swapfile.c \
  && ok "swapfile nandswap device filter" || fail "swapfile nandswap filter missing"
grep -q "current_is_nswapoutd" mm/swap_slots.c \
  && ok "swap_slots nswapoutd bypass" || fail "swap_slots nswapoutd bypass missing"
grep -q "CONFIG_NANDSWAP=y" arch/arm64/configs/vendor/xiaomi/miatoll_defconfig \
  && ok "defconfig: CONFIG_NANDSWAP=y" || fail "defconfig lost CONFIG_NANDSWAP=y"

echo "== MGLRU (Multi-Gen LRU)"
grep -q "^config LRU_GEN$" mm/Kconfig \
  && ok "LRU_GEN Kconfig present" || fail "mm/Kconfig missing LRU_GEN"
grep -q "^config LRU_GEN_ENABLED$" mm/Kconfig \
  && ok "LRU_GEN_ENABLED Kconfig present" || fail "mm/Kconfig missing LRU_GEN_ENABLED"
grep -q "lru_gen_enabled" mm/vmscan.c \
  && ok "vmscan gen-LRU core present" || fail "vmscan gen-LRU core missing"
grep -q "lru_gen_look_around" mm/rmap.c \
  && ok "rmap locality hook present" || fail "rmap look-around hook missing"
grep -q "lru_gen_use_mm" include/linux/mm_types.h \
  && ok "page-table walk mm hook present" || fail "page-table walk mm hook missing"
grep -q "DEFINE(LRU_GEN_WIDTH" kernel/bounds.c \
  && ok "kernel/bounds.c reserves page-flag bits" || fail "bounds.c LRU_GEN_WIDTH missing"
grep -q "struct lru_gen_struct" include/linux/mmzone.h \
  && ok "lruvec gen-LRU fields present" || fail "lruvec gen-LRU fields missing"
for opt in CONFIG_LRU_GEN=y CONFIG_LRU_GEN_ENABLED=y; do
  grep -q "$opt" arch/arm64/configs/vendor/xiaomi/miatoll_defconfig \
    && ok "defconfig: $opt" || fail "defconfig lost $opt"
done

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

echo
if [ "$FAIL" -ne 0 ]; then
  echo "AUDIT FAILED"
  exit 1
fi
echo "AUDIT PASSED"
