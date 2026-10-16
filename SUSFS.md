# KernelSU-Next + SUSFS v2.3.0 (miatoll, kernel 4.14)

## What is in the tree

| Path | Role |
| --- | --- |
| `drivers/kernelsu/` | KernelSU-Next **v3.4.0** (`legacy-susfs-v2`), vendored in-tree |
| `fs/susfs.c` | the SUSFS kernel half (v2.3.0) |
| `include/linux/susfs.h`, `include/linux/susfs_def.h` | SUSFS structs, supercall IDs, KABI bits |
| `kernel/configs/miatoll/susfs.config` | config fragment (merged by `scripts/merge-defconfig.sh`) |

Hook sites (all guarded by the matching `CONFIG_KSU_SUSFS_*` option):

* `fs/namei.c` – SUS_PATH (lookup) and OPEN_REDIRECT (`readlink`)
* `fs/readdir.c` – SUS_PATH in the `getdents`/`old_readdir` fillers
* `fs/namespace.c` – SUS_MOUNT id allocation, `__lookup_mnt()` spoofing,
  `clone_mnt()`/`copy_mnt_ns()`, `susfs_get_non_sus_{mnt_id,vfsmnt}_from_*()`,
  plus the `can_umount()`/`path_umount()` backport KernelSU-Next needs
* `fs/super.c` – `get_anon_bdev()` gives KSU mounts a high minor number
* `fs/stat.c`, `fs/statfs.c`, `fs/notify/fdinfo.c`, `fs/proc/fd.c` – SUS_KSTAT
* `fs/proc_namespace.c` – `/proc/<pid>/{mounts,mountinfo,mountstats}`
* `fs/proc/task_mmu.c`, `mm/memory.c` – SUS_MAP (`maps`, `smaps`, `pagemap`,
  `/proc/<pid>/mem`), OPEN_REDIRECT in `show_map_vma()`
* `fs/proc/base.c` – `readlink` redirect, `map_files` filtering
* `fs/proc/cmdline.c` – spoofed `/proc/cmdline`
* `kernel/sys.c` – spoofed `uname()`
* `kernel/kallsyms.c` – hide `ksu_*`/`susfs_*` symbols
* `security/selinux/avc.c` – AVC log spoofing (active when `CONFIG_AUDIT=y`)

## Hooking mode

4.14 has no `pt_regs`-based syscall ABI (that landed in 4.17), so the
syscall-table hook is unavailable: the tree builds KernelSU-Next with
`CONFIG_KSU_KPROBES_HOOK=y` (tracepoint + kretprobe).  No kernel-side manual
hooks (`ksu_handle_*` calls in `fs/exec.c`, `fs/open.c`, ...) are used — the
hook manager dispatches `newfstatat`, `faccessat`, `execve{,at}` and
`setresuid` by itself, and `setresuid` is where SUSFS `try_umount` runs.

## Feature set

Enabled: `SUS_PATH`, `SUS_MOUNT`, `SUS_KSTAT`, `TRY_UMOUNT`, `SPOOF_UNAME`,
`ENABLE_LOG`, `HIDE_KSU_SUSFS_SYMBOLS`, `SPOOF_CMDLINE_OR_BOOTCONFIG`,
`OPEN_REDIRECT`, `SUS_MAP`.

Deliberately **off**: `SUS_MEMFD` — it is marked experimental upstream, needs
the `__cleanup()` infrastructure backport, and was reverted downstream too.
The CI config check asserts it stays off.

## Verifying a running build

The `ksu_susfs` userspace tool shipped with the matching SUSFS release talks to
these supercalls:

```
ksu_susfs show version      # -> v2.3.0
ksu_susfs show variant      # -> NON-GKI
ksu_susfs show enabled_features
```

Use a `ksu_susfs` binary built for **v2.3.0**; an older tool does not know the
v2.x command/struct layout.

## Notes / limits

* SUSFS stores its flag bits in `inode->i_state` (bits 33–39), which is free on
  this kernel — `i_mapping->flags` must not be used for that any more.
* `TIF_PROC_UMOUNTED` uses thread-info bit 33; the highest arm64 `TIF_` flag in
  this tree is 25, so there is no overlap.
* The AVC-log spoofing hunk lives inside `#ifdef CONFIG_AUDIT`, so it is a
  no-op while `CONFIG_AUDIT` is off (the defconfig leaves it off).
* KernelSU-Next's Makefile normally `sed`-patches the kernel tree at build time
  to add `path_umount()` and `struct seccomp.filter_count`.  Both are committed
  here instead, so the build no longer mutates tracked sources.
