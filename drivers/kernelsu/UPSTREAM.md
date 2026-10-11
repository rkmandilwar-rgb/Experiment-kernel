# KernelSU upstream provenance

This directory vendors the kernel component from:

- Repository: https://github.com/backslashxx/KernelSU
- Tag: `v3.3.0+72` (upstream kernel Makefile: KSU_VERSION 32673)
- Imported from the upstream `kernel/` directory verbatim, plus the local
  SUSFS glue blocks listed below.
- Manager policy: upstream stock. The tree accepts exactly the managers the
  upstream `v3.3.0+72` release accepts (backslashxx release manager on the
  public dummy.keystore cert, package `me.weishu.kernelsu`, and self-built
  managers on the official KernelSU cert). `manager/apk_sign.c` and
  `manager/throne_tracker.c` are pristine upstream.

It is integrated in-tree for the Linux 4.14 non-GKI Miatoll kernel
(curtana / gram / joyeuse / excalibur, 4.14.357-openela base).

## Integration method

- Scope-minimized manual hooks, after backslashxx/KernelSU issue #5,
  manual-hooks revision v2.3:
  - `fs/exec.c` -> `ksu_handle_execveat()` in `do_execveat_common()`
  - `kernel/reboot.c` -> `ksu_handle_sys_reboot()` in `SYSCALL reboot`
    (compiled only when `CONFIG_KSU_KPROBES_KSUD` is off, which it is here)
- `CONFIG_KSU_LSM_SECURITY_HOOKS=y` provides the cred/setuid hooks
  (`hook/lsm_hooks_*`); the setuid hook carries the SUSFS umount glue.
- Kprobe hooks, syscall-table tampering and ARM64 branch-link hooks are
  intentionally disabled in the Miatoll defconfig.

## Local SUSFS v2.3.0 glue (not present upstream)

Upstream backslashxx/KernelSU ships no SUSFS support. The following local
blocks bridge SUSFS v2.3.0 (see `fs/SUSFS_UPSTREAM.md`) into the driver;
they were carried over from the hardware-validated Stormbreaker/CustomKernel1
4.14 integration and re-applied on the `v3.3.0+72` sync:

- `Kconfig` — the "KernelSU - SUSFS" menu (`KSU_SUSFS` + feature toggles;
  `KSU_SUSFS` depends on `FUSE_FS` because `fs/susfs.c` uses fuse internals).
- `ksu.c` — `#include <linux/susfs.h>` and `susfs_init()` before
  `ksu_supercalls_init()`. The include also feeds the unity build, so
  `supercall.c` / `setuid_hook.c` see the SUSFS UAPI and inlines.
- `hook/setuid_hook.c` — in `ksu_handle_setresuid_cred()`: mark app /
  isolated / webview-zygote uids with `susfs_set_current_proc_umounted()`
  before the kernel-umount work, then `schedule_work(&susfs_extra_works)`
  to re-apply looped sus-path marks after the umount work completes.
- `selinux/selinux.c` — `susfs_is_current_ksu_domain()` (== `is_ksu_domain()`).
- `supercall/supercall.c` — the SUSFS command block in `ksu_handle_sys_reboot()`:
  `magic2 == SUSFS_MAGIC` (0xFAFAFAFA) + root caller dispatches the
  `CMD_SUSFS_*` (0x555xx/0x600xx) v2.3.0 userspace ABI. This is the channel
  the `ksu_susfs` tool (and therefore the BRENE module) uses on this fork,
  since the fork has no `prctl(KERNEL_SU_OPTION)` hook.
- `supercall/dispatch.c` — atomic `EVENT_POST_FS_DATA` one-shot
  (`atomic_cmpxchg`), `susfs_start_sdcard_monitor_fn()` on that one-shot,
  and `ksu_module_mounted = true` on `EVENT_MODULE_MOUNTED`.

## Sync history

- 2026-10-11: vendored `v3.3.0+72` pristine and re-applied the six local
  SUSFS glue blocks on top (port of the validated glue that rode on the
  `v3.3.0-60`-era tree; upstream `ksu_handle_execveat()` /
  `ksu_handle_sys_reboot()` / `ksu_handle_setresuid_cred()` /
  `ksu_module_mounted` / `is_appuid` / `is_isolated_process` /
  `WEBVIEW_ZYGOTE_UID` anchors are unchanged between the two tags).
  Local manager-policy trims from the previous lineage (KOWX712 removal,
  two-manager crowning) were intentionally NOT carried over — upstream
  stock manager acceptance is used.
