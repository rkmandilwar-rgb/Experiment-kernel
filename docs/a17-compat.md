# Android 17 on a 4.14 kernel — what was changed and why

Android 17 (API 37, LineageOS 24.0) still runs on 4.14 hardware, but only on
trees that carry a small set of backports.  LineageOS announced 24.0 on
2026-10-11 and keeps 4.14 in scope for Qualcomm devices; 4.4/4.9 are frozen at
22.2.  The kernel-side delta for miatoll is smaller than the announcements
suggest — the userspace/ROM side does most of the work.

This file records every change we applied, the tree it came from, and how it
differs from the reference implementation.

## Reference trees

| Tree | What it is | Version |
|---|---|---|
| `AbdoAhmedElbanaa/kernel_xiaomi_sm6250` @ `17` | miatoll kernel maintained for Android 17 | 4.14.357, tip `0ae171f2bde2` (2026-10-19) |
| `LineageOS/android_kernel_xiaomi_sm6125` @ `lineage-24.0` | 4.14 device family shipping A17 | 4.14.357 |
| `LineageOS/android_kernel_google_msm-4.14` (Pixel 4) @ `lineage-24.0` | independent 4.14-on-A17 data point | 4.14.357 |

The Abdo tree carries both boot patches in exactly the form used below; the
sm6125 and Pixel trees were used to confirm the same two commits are the whole
kernel-side requirement (`519534f9a`, `f89128047`).

## Applied

| # | Change | Where | Reference |
|---|---|---|---|
| 1 | Append `androidboot.force_normal_boot=1` to `/proc/cmdline` when the bootloader sends `skip_initramfs`, so two-stage init takes the normal-boot path instead of stalling | `fs/proc/cmdline.c`, `fs/proc/Kconfig:92` | Abdo `17`, `fs/proc/cmdline.c:8-30`, `fs/proc/Kconfig:93` |
| 2 | `INITRAMFS_IGNORE_SKIP_FLAG` (default **n**): lets the ramdisk win over a bootloader `skip_initramfs` | `usr/Kconfig:35`, `init/initramfs.c:618` | sm6125 `519534f9a` |
| 3 | `CONFIG_AUDIT=y`: without it SELinux compiles its audit path out, no `avc:` record exists and the SUSFS AVC-log spoof has nothing to rewrite | `kernel/configs/miatoll/a17.config:29` | Abdo `17` defconfig `:773`, LineageOS sm8150/sm6250 |
| 4 | EROFS per-CPU decompression workers | `kernel/configs/miatoll/erofs.config:25-26` | Abdo `17` defconfig, crDroid sm8150 `17.0` |

### Deliberate differences from the reference implementation

- **Bounds checking.** The reference appends with a `memcpy` that can write past
  `COMMAND_LINE_SIZE` when the cmdline is full.  Ours sizes the copy:

  ```c
  if (strstr(saved_command_line, INITRAMFS_STR_FIND) &&
      len + sizeof(FORCE_NORMAL_BOOT_STR) <= sizeof(proc_command_line))
          memcpy(proc_command_line + len, FORCE_NORMAL_BOOT_STR,
                 sizeof(FORCE_NORMAL_BOOT_STR));
  ```

- **SUSFS ordering.** `susfs_spoof_cmdline_or_bootconfig()` still runs first
  (`fs/proc/cmdline.c:66`); the new buffer only replaces the fallback print, so
  a spoofed cmdline keeps winning.

- **Patch 2 stays off.** Enabling it changes the boot path on every device; it
  exists as an escape hatch, not a default.

## Considered and rejected

| Option | Why not |
|---|---|
| `CONFIG_KALLSYMS_ALL` | Only needed by syscall-table/kprobe hooking; this tree uses `KSU_MANUAL_HOOK`. It would also expose every data symbol in `/proc/kallsyms`, defeating SUSFS symbol hiding. |
| `CONFIG_LD_DEAD_CODE_DATA_ELIMINATION` | Size optimisation, not an A17 requirement; turns on `--gc-sections`, which needs a linker-script audit first. |
| `CONFIG_HZ_100` (both reference trees) | Scheduling latency trade-off, unrelated to the A17 boot path. |
| Pixel msm-4.14 set (`85ab0ac3d`, `f9425e3e4`, `48b9bf0`, `823c5689a`, `bb17b7de4`) | Dead code — helpers with no callers once the Android 17 path is enabled. |
| `VMAP_STACK` flip | Both miatoll A17 trees disable it, but there is no proven mechanism tying it to the logo hang; correlation only, so unchanged. |

## Verification

```
$ scripts/check-config-fragments.sh
Checking 18 fragment(s) - no generated config, symbol existence only
checked 520 options, 0 missing symbol(s), 0 ineffective option(s)
```

Build 187 (`8041e8a2f`, run `39649701170`) is the first green build carrying
this set.
