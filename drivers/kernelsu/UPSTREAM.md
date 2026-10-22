# KernelSU upstream provenance

This directory vendors the kernel component from:

- Repository: https://github.com/backslashxx/KernelSU
- Release/tag: `v3.3.1-22` (kernel driver constant `KSU_VERSION=32700`, **UAPI v6**)
- Matching Manager release asset: `KernelSU_v3.3.1-22_32702-release.apk`
  (Manager version code 32702 pairs with the unchanged 32700 driver constant)
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
- `supercall/dispatch.c` — atomic `EVENT_POST_FS_DATA` one-shot guard and
  `susfs_start_sdcard_monitor_fn()` on that one-shot. `ksu_module_mounted`
  is no longer set here: upstream `runtime/boot_event.c`
  (`on_module_mounted()`) owns it as of v3.3.1-22.

## Sync history

- 2026-10-22: refreshed the vendored driver to backslashxx/KernelSU
  `v3.3.1-22` (driver constant still `KSU_VERSION=32700`, UAPI v6; Manager
  `KernelSU_v3.3.1-22_32702-release.apk`) and reapplied the local SUSFS glue.
  The `kernel/` subtree is a straight import of upstream `v3.3.1-22`; only the
  six glue files below differ from it. What moved upstream and changed our
  local setup:
  - **Legacy / non-GKI kernel support.** New `hook/lsm_hooks_ultralegacy.c`,
    `kernel: prepare for legacy support`, `compat: squash ALL compat shims`,
    `lsm_hook: bprm: escape init ksud call to root for < 4.14`,
    `adapt "namespace support" feature to old kernels`,
    `feature: umount: wire up path_umount compat`. This is the series that
    matters for 4.14 trees like ours.
  - **Mount-namespace + module rc injection fixes.** `su_mount_ns: move
    ksys_unshare to ksyscall`, `ksud: read: add fallback to /init.rc`,
    `handle newfstat init_rc size injection`, `handle early newfstat
    module_rc size injection`, `migrate ksu_install_rc_hook to
    security_file_permission LSM`, `Fix init.rc detection for bind-mounted
    files`, `Add module preinit`, `ksud: preinit: extract a bit more
    /metamodule space`. These are the paths a metamodule exercises during
    post-fs-data, i.e. the suspected cause of the boot-logo hangs reported
    on Android 17 (Infinity X 4.x) with v3.3.1-21.
  - **Local quirks dropped, now upstream:** preinit is disabled upstream via
    `KSU_NO_PREINIT` in `preinit/preinit.h` whenever jump labels are
    unavailable (our arm64 4.14 build), so the local `-DKSU_NO_PREINIT`
    Makefile flag is gone; `ksu_module_mounted` is set by
    `runtime/boot_event.c`; `MODULE_RC_MAX` clamping now covers the read
    path upstream.
  - **Local build fixes re-checked.** The fortify/`assume()`/`4.14 syscall
    wrapper` fixes from the -21 refresh are no longer needed as local
    patches: upstream -22 carries its own `assume()` compat, absolute
    `ksyscall` wrappers and the `#else`-free `ksys_unshare` shim.
  Note: upstream deleted the `v3.3.1-21` release and its assets (the tag
  `v3.3.1+21` remains, pointing at newer content), so release jobs must pin
  `v3.3.1-22` and fall back to a mirrored Manager asset.

- 2026-10-21: refreshed the vendored driver to backslashxx/KernelSU
  `v3.3.1-21` (`KSU_VERSION=32700`, UAPI v6) and reapplied the local SUSFS
  glue. Matching Manager is `KernelSU_v3.3.1-21_32701-release.apk`
  (version code 32701). Driver delta vs v3.3.1-13: `ksud` split into
  `runtime/ksud_integration.c` + `runtime/boot_event.c` (+ `ksud_boot.h`),
  `ksu_file_sid` moved to `selinux.h`, adb_root calls became no-op macro
  stubs, execve paths gained preinit hook points, branch-link hook helpers
  refactored to generic macros, `get_info` reports `KSU_GET_INFO_FLAG_PREINIT`,
  `module_rc_len` capped at `MODULE_RC_MAX` upstream (the read-path `fsize`
  clamp stays a local fix), and the late-load LKM escape is `#if 0` upstream
  now. Local quirks kept: preinit stays NOT IMPLEMENTED via
  `-DKSU_NO_PREINIT` in the Makefile (upstream would auto-enable it through
  `KSU_CAN_USE_JUMP_LABEL` on arm64), plus the usual fortify/`assume()`/
  `__builtin_memcpy`/4.14 syscall-wrapper build fixes. Note: upstream deleted
  the v3.3.1-13 release/tag after shipping v3.3.1-21, so release jobs must
  pin the new tag.

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
