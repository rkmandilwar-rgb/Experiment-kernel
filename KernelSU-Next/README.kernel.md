# KernelSU Next (non-GKI) — vendored driver

This directory is a **vendored snapshot of [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next)**
(the community KernelSU fork by rifsxd), integrated into this non-GKI
4.14 kernel as a **built-in driver with manual VFS hooks**.

| | |
|---|---|
| Upstream | `https://github.com/KernelSU-Next/KernelSU-Next` |
| Branch | `legacy` (the non-GKI / LTS line: 4.x–5.4, 3.x experimental) |
| Pinned commit | `0b17f24246db5c80c056b92c15bcad2b77f1276e` (2026-10-17) |
| Feature level | v3.4.2 (3.4.2 feature ports on the legacy line; last tag `v3.4.0-legacy`) |
| Reported driver version | `33355` / `v3.4.2-legacy-g0b17f242` (pinned in the top-level `Makefile`) |
| Manager | `KernelSU_Next_v3.4.2_33355-release.apk` ([releases](https://github.com/KernelSU-Next/KernelSU-Next/releases)) — or the `-spoofed` variant |

Contents mirror upstream `kernel/`, `uapi/`, `LICENSE` verbatim.  The
`kernel/include/uapi -> ../../uapi` symlink is upstream's and must survive
updates.  Two caveats (both bit us once — see git history):

* Upstream's `.gitignore` says plain `manager` / `userspace`, which git
  matches at **any** depth — it silently swallowed the driver's own
  `kernel/manager/` sources (`apk_sign`, `throne_tracker`,
  `manager_identity/observer`, `pkg_observer`) on first vendor.  The
  patterns here are anchored (`/manager`, `/userspace`); keep them that way.
* The kernel repo's top-level `.gitignore` has `.*`, which hides upstream's
  tracked dotfiles (`kernel/.clang-format`, `kernel/.clangd`,
  `kernel/.vscode/`).  They are force-added once; `git add -f` them again
  after an update if upstream adds new ones.

## How it is wired in (what to redo after an update)

Exactly what upstream's `kernel/setup.sh legacy` does, but vendored (no
runtime clone, no symlink to a sibling clone — reproducible CI builds):

1. `drivers/kernelsu` → symlink to `../KernelSU-Next/kernel`
2. `drivers/Makefile` — `obj-$(CONFIG_KSU) += kernelsu/`
3. `drivers/Kconfig` — `source "drivers/kernelsu/Kconfig"`
4. `kernel/configs/miatoll/kernelsu.config` — `CONFIG_KSU=y` +
   `CONFIG_KSU_MANUAL_HOOK=y` (merged last by `scripts/merge-defconfig.sh`)
5. Top-level `Makefile` — `KSU_VERSION_OVERRIDE` / `KSU_VERSION_TAG_OVERRIDE`
   (the driver otherwise reports version `1` when vendored in the kernel's
   own git repo; keep these in sync with the Manager APK versionCode)
6. Manual hook call sites (see below)

## Hook mode: MANUAL (why)

On this 4.14 tree the KSU Kconfig's automatic choices are wrong:

* **kprobe/tracepoint hooks** — "should not be used on kernel below 5.10"
  (and many 4.x kernels have buggy kprobes that silently break root);
* **syscall-table patching** — requires ≥ 4.17 (pt_regs syscall ABI).

`CONFIG_KSU_MANUAL_HOOK=y` is therefore pinned explicitly (it must NOT be
left to `default y if !KPROBES` — the eBPF pack enables KPROBES).  The
driver's `kernel/Kbuild` asserts the manual hooks exist (`ksu_handle_sys_reboot`
in `kernel/reboot.c`) and refuses to build otherwise.

### Call sites (scope-minimized shape)

All guarded by `#ifdef CONFIG_KSU` and marked `KernelSU Next (non-GKI)`:

| File | Function | Entry point (driver) |
|---|---|---|
| `fs/exec.c` | `do_execveat_common` | `ksu_handle_execveat` / `ksu_handle_execveat_sucompat` (switch on `ksu_execveat_hook`) |
| `fs/open.c` | `SYSCALL_DEFINE3(faccessat)` | `ksu_handle_faccessat` |
| `fs/read_write.c` | `vfs_read` | `ksu_handle_vfs_read` (guard `ksu_vfs_read_hook`) |
| `fs/stat.c` | `vfs_statx` | `ksu_handle_stat` |
| `kernel/reboot.c` | `SYSCALL_DEFINE4(reboot)` | `ksu_handle_sys_reboot` (supercall channel — **required**) |
| `drivers/input/input.c` | `input_handle_event` | `ksu_handle_input_handle_event` (guard `ksu_input_hook`, 3×VolDown safe mode) |

This is the same layout susfs4ksu's non-GKI "manual hooks" patches are
written against.  Do not move/rename these call sites without a reason —
future SUSFS patches patch *around* them.

Not hooked (on purpose): `fs/devpts/inode.c` and `fs/namespace.c` (the
legacy driver covers pts/umount via its LSM hooks — `task_fix_setuid`,
`inode_rename`, `inode_permission` — registered from
`kernel/hook/lsm_hooks.c` when kprobes are not used).  `can_umount`/
`path_umount` backports for older kernels are inserted automatically by
`kernel/Kbuild` at build time (see below).

## Build-time tree patching by `kernel/Kbuild` (heads-up)

Upstream's `kernel/Kbuild` contains compat backports implemented as `sed`
edits **against the kernel source tree at build time** (e.g. `can_umount`/
`path_umount` in `fs/namespace.c`, seccomp `filter_count`, SELinux
`selinux_inode()`/`selinux_cred()` helpers).  On this tree most of them are
already present and the rest self-insert before compile.  Consequences:

* a local `make` can dirty `fs/namespace.c`, `fs/internal.h`,
  `include/linux/seccomp.h`, `security/selinux/*` in `git status` — the
  edits are idempotent and CI always starts from a clean checkout;
* if you commit those generated edits, later KSU updates and SUSFS patches
  may no longer apply cleanly.  Leave them uncommitted.

## Updating the vendored driver

```sh
curl -fsSL -o /tmp/ksun.tar.gz \
  https://codeload.github.com/KernelSU-Next/KernelSU-Next/tar.gz/refs/heads/legacy
tar -xzf /tmp/ksun.tar.gz -C /tmp
rsync -a --delete --exclude='.gitignore' /tmp/KernelSU-Next-legacy/kernel/ KernelSU-Next/kernel/
rsync -a --delete /tmp/KernelSU-Next-legacy/uapi/ KernelSU-Next/uapi/
cp /tmp/KernelSU-Next-legacy/LICENSE KernelSU-Next/
# manager/ and the upstream dotfiles are easy to lose to ignore rules -
# force-add them so the build never loses headers again:
git add -A KernelSU-Next
git add -f KernelSU-Next/kernel/manager KernelSU-Next/kernel/.clang-format \
           KernelSU-Next/kernel/.clangd KernelSU-Next/kernel/.vscode
# then: update KSU_VERSION_OVERRIDE / KSU_VERSION_TAG_OVERRIDE in the
# top-level Makefile and the table above; rebuild via CI.
```

## Backporting SUSFS (v2.3.0) later — the plan

This is the reason the integration is shaped the way it is.  susfs4ksu's
non-GKI instructions (upstream: `simonpunk/susfs4ksu`, `kernel-4.14` branch;
GitHub mirrors such as `sidex15/susfs4ksu-begonia`) split into three parts,
all of which slot straight into this layout:

1. **Kernel-side SUSFS core** — `kernel_patches/fs/*` → `fs/`,
   `kernel_patches/include/linux/*` → `include/linux/`, then apply
   `50_add_susfs_in_kernel-4.14*.patch` at the kernel root (`patch -p1`).
   Its hunks touch `fs/stat.c`, `fs/namespace.c`, `fs/dcache.c`,
   `fs/namei.c`, `kernel/sys.c`, `kernel/kallsyms.c` … — our KSU call
   sites use the same "minimized hook" contexts those patches expect.
2. **KSU-side SUSFS** — the KSU-driver patch (e.g.
   `10_enable_susfs_for_ksu.patch` or the KernelSU-Next-specific variant)
   is applied **inside this directory** (`cd KernelSU-Next && patch -p1 …`),
   exactly as the susfs4ksu README instructs (`$KERNEL_ROOT/KernelSU/` for
   stock KSU ≙ `$KERNEL_ROOT/KernelSU-Next/` here).  Its hunks target
   `kernel/...` paths, which map to `KernelSU-Next/kernel/...`.
3. **SUS_SU** — must stay **disabled** on non-GKI manual-hook kernels
   (`CONFIG_KSU_SUSFS_SUS_SU=n`); enable the `CONFIG_KSU_SUSFS_*` options
   the patch adds via a new `kernel/configs/miatoll/susfs.config` fragment
   (merge order: after `kernelsu.config`).

When picking the SUSFS version, prefer the same KSUN generation the susfs
patches were cut against (the "generic" KSUN SUSFS patch expects
`ksu_handle_post_execveat_sucompat` in `feature/sucompat.c` — present in
KSUN ≥ 3.4 legacy snapshots).  If a hunks fails, the usual cause is the
`kernel/Kbuild` build-time backports above having been committed.

## CI

`.github/workflows/build.yml` builds the kernel with this driver compiled
in (`CONFIG_KSU=y` is asserted in the config-verification step, along with
the six manual hook call sites) and uploads the flashable zip as a workflow
artifact.  **Nothing is ever published to GitHub Releases** — the release
job is permanently gated with `if: false` and a guard step fails the build
if that gate is removed.

On a failed build the workflow also commits the diagnostics
(`build.log`, `build-errors.txt`, `fragment-check.log`, `out/.config`,
`RUN.txt`) to `ci-logs/` on the same branch — with `[skip ci]`, so it never
re-triggers a build — which makes the error output readable straight from
the repo.
