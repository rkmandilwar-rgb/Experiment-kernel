# KernelSU upstream provenance

This directory vendors the kernel component from:

- Repository: https://github.com/backslashxx/KernelSU
- Release/tag: `v3.3.1-13` (kernel driver `KSU_VERSION=32693`, **UAPI v6**)
- Matching Manager release asset: `KernelSU_v3.3.1-13_32693-release.apk`
- The upstream `kernel/` subtree is imported, with only the local SUSFS v2.3.0
  glue documented below reapplied.
- The driver exposes KernelSU UAPI v6, which the matching Manager requires
  (kernel and Manager must update together).
  Upstream notes that existing app profiles may reset during this update.

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
blocks bridge SUSFS v2.3.0 (see `fs/SUSFS_UPSTREAM.md`) into the driver; they
are retained across the `v3.3.1` refresh:

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
- `supercall/supercall.c` — the SUSFS command block in
  `ksu_handle_sys_reboot()`: `magic2 == SUSFS_MAGIC` (0xFAFAFAFA) + root
  caller dispatches the `CMD_SUSFS_*` (0x555xx/0x600xx) v2.3.0 userspace ABI.
  This is the channel the `ksu_susfs` tool (and therefore BRENE) uses on this
  fork, since the fork has no `prctl(KERNEL_SU_OPTION)` hook.
- `supercall/dispatch.c` — atomic `EVENT_POST_FS_DATA` one-shot guard,
  `susfs_start_sdcard_monitor_fn()` on that one-shot, and
  `ksu_module_mounted = true` on `EVENT_MODULE_MOUNTED`.

## Sync history

- 2026-10-18: refreshed the vendored driver to backslashxx/KernelSU
  `v3.3.1-13` (`KSU_VERSION=32693`, **UAPI v6** — kernel and Manager must
  update together; profiles may reset) and reapplied the local SUSFS glue +
  fortify/`assume()` build fixes. Driver delta vs the previous snapshot:
  `LOOKUP_SYMBOLS` supercall (root-only), module preinit stubs, shell-su
  allowance check (tiann #3882), midori supermanager recognition, deferred
  setprocattr overload, `kvmalloc` `__GFP_ZERO` fix, `kvcalloc` shim, and the
  module late-load escape disabled (`#if 0`; the init.rc second-stage path
  remains the one that caches SIDs). Matching Manager is
  `KernelSU_v3.3.1-13_32693-release.apk` (version code 32693). Note: upstream
  deleted the v3.3.1-11 release (like v3.3.0-79 before it).

- 2026-10-13: refreshed the vendored driver to backslashxx/KernelSU
  `v3.3.1` and reapplied the local SUSFS glue + `kernel_compat.h` build
  fixes. The `kernel/` subtree is byte-identical to the previous
  `v3.3.0-79` (tag `32676`) base — v3.3.1 is a Manager/userspace release —
  so the driver stays `KSU_VERSION=32676`, UAPI v5. The matching release
  Manager is v3.3.1 (`KernelSU_v3.3.1_32680-release.apk`, version code
  32680); the old v3.3.0-79 GitHub release was deleted upstream, which is
  what broke the previous release job. Driver and Manager are released
  together.
- 2026-10-12: refreshed the vendored driver to backslashxx/KernelSU
  `v3.3.0-79` (`KSU_VERSION=32676`, UAPI v5), including upstream's latest
  feature and compatibility updates, then reapplied the local SUSFS glue.
  The matching release Manager is v3.3.0-79 (version code 32680). Upstream
  warns that profiles may reset; driver and Manager are released together.
- 2026-10-11: previously vendored backslashxx/KernelSU `v3.3.0+72` and
  reapplied the six local SUSFS glue blocks on top.
