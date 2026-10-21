# `Saamitk/Kinesis` — deep review of every branch, and the delta against Stormbreaker

**Date:** 2026-10-21
**Reviewed tree:** `Saamitk/Kinesis` (fork of `AzyrRuthless/kernel_xiaomi_sm6250`), branch `17` @ `e0a1126c9`, branch `16` @ `4afc6f0769`
**Reference tree:** this repo, `arena/53729e17-experiment-kernel` @ `c6969b508`

---

## 0. Verdict

Branch `17` is a **4.14.357-openela** tree with **SUSFS v2.3.0**, **NoMount v20** and a **different root driver**
(`backslashxx/KernelSU`, `KSU_VERSION=32657`, unity build) — not a newer version of the KernelSU-Next stack we run.
It is **not a reference to copy**: as committed, its own build path cannot produce a display-capable kernel
(no `CONFIG_DRM_MSM`), and the SELinux AVC spoof it carries leaks memory on its spoof path.

Our tree is **ahead** on: LTS/scheduler content, AVC-spoof implementation, installer correctness, kallsyms type
correctness, and it carries features they do not have (`process_reclaim`, `perf_trace_counters`, `ntfs3`).
Our tree is **behind** on exactly four things: the `/proc/kallsyms` denylist is far too narrow (live detection gap),
`ss/services.c` still uses `BUG()` where they harden it, the GENI UART `device_pending_suspend()` predicate keeps a
pre-fix `||`, and we have no `CONFIG_AUDIT` — which silently disables our own AVC-spoof feature.

Nothing here requires rebuilding the root stack. Three small patches and one config decision are the whole action list
(§9).

---

## 1. Scope, method, limits

| | |
|---|---|
| Common files compared | **72,749** |
| Files whose size differs | **843** |
| Directories compared line-by-line | `fs`, `kernel`, `mm`, `security`, `include/linux`, `arch/arm64/kernel`, `drivers/kernelsu` — **327 entries** |
| Verdict per file | 29 root-stack hooks · 187 base-lineage · 56 KSU-variant · 39 ours-only · 16 theirs-only |

Method: full clone of branch `17` (depth 1 + depth 40), explicit fetch of `origin/16`, `diff -rq` per directory,
then `diff -u` per file with hunk counting and token classification (`susfs`, `KSU_SUSFS`, `nomount`, `ksu_`,
`FAKE_UNAME`, …). Every file in the seven directories was diffed; the 187 "base lineage" files were triaged by
hunk content, not hand-read line-by-line — the ledger in Appendix A names each one with its line counts so any
claim can be spot-checked.

**Limit, stated plainly:** there is no cross-compiler in this environment. Nothing here was built or booted.
Conclusions are static, or drawn from upstream/reference trees (LineageOS `lineage-20`/`lineage-22.2`,
`AzyrRuthless` branch `16`). Runtime claims are marked **UNVERIFIED**.

Outside the seven audited directories the two trees diverge in another ~516 files by size (WireGuard compat,
`ashmem`, `lpm-levels`, `ufs-qcom`, `ds28e16`, KGSL/Adreno, …). Those are base-lineage differences: our tree
imports an ELTS/4.19-derived manifest (`.elts/upstream/4.19.323.yaml`) that theirs does not have. They are listed
in Appendix A.2 by size delta and were not reviewed function-by-function.

---

## 2. Branch map

| Branch | SHA | Role | Root stack |
|---|---|---|---|
| `16` (default) | `4afc6f0769` | 4.14.357-openela + LTO/Polly, Xiaomi atoll base | **none** — no `fs/susfs.c`, no `fs/nomount/`, no `drivers/kernelsu/` |
| `17` | `e0a1126c9` | the "Saamrox root stack" branch | KernelSU 32657 + SUSFS 2.3.0 + NoMount 20 |
| `arena/01a10cec-kinesis` | `e0a1126c9` | **stale duplicate of `17`** (same object) | same |

`16 → 17` is **139 files, +25,773 / −58** (113 added, 26 modified). So "check all its branches" reduces to:
branch 16 carries no root code at all, and everything interesting happens in a single squashed import plus three
follow-up commits:

```
b032e75d3  Kinesis: Saamrox root stack (KernelSU, SuSFS, NoMount, DroidSpaces) + clang CI
3d955e5d8  haptics: port the maintained AW8624 driver (arshad-jamil33@16.2)
c5408bac8  ak3: fix the flashable installer, it aborted on every recovery
e0a1126c9  build: ignore the zip verification directory too
```

The 26 modified files between the branches are exactly the root-stack integration points — `fs/namei.c`,
`fs/namespace.c`, `fs/proc/{base,cmdline,fd}.c`, `fs/{stat,statfs,readdir,super}.c`, `fs/proc_namespace.c`,
`fs/notify/fdinfo.c`, `mm/memory.c`, `kernel/{kallsyms,sys}.c`, `security/selinux/avc.c`, the two `Kconfig`s,
`drivers/Kconfig`, `.gitignore`, the defconfig, the haptics driver — plus one unrelated cleanup,
`net/core/netprio_cgroup.c` + `include/net/netprio_cgroup.h` switching `css->cgroup->id` → `css->id`
(both fields exist in both trees at `include/linux/cgroup-defs.h:132/148`; semantically identical, no action).

---

## 3. Their root driver is a different project

| | Stormbreaker (ours) | Kinesis `17` |
|---|---|---|
| Project | `KernelSU-Next` **v3.4.2 / 33355** | `backslashxx/KernelSU` **`KSU_VERSION=32657`** (`drivers/kernelsu/Makefile:16`) |
| Build model | separate objects, 144 files | **unity build**, one unit (`Makefile:1-3`), 82 files |
| Hook method | `CONFIG_KSU_MANUAL_HOOK=y` | `KSU_HACK_ARM64_BRANCH_LINK` / `KSU_TAMPER_SYSCALL_TABLE` / `KSU_KPROBES_KSUD` |
| Extra dirs | `hook/syscall_table_hook.c`, `infra/symbol_resolver.c`, `hook/patch_memory.c` | `downstream/`, `external/chibihash64.h`, `hook/kp_ksud.c`, `hook/branch_link_hook_arm64.c` |
| Data symbols | resolved at runtime, non-fatal if missing | requires `KALLSYMS_ALL` (they gate it in `build.sh:87-89`) |
| SUSFS | v2.3.0, our own implementation | v2.3.0, upstream patch text |
| NoMount | **v21** (`fs/nomount/nomount.h:18`) | **v20** (`fs/nomount/nomount.h:19`) |

Consequence: the 56 `drivers/kernelsu/*` rows in the ledger are **not** "missing features" on our side — they are a
different program with a different hook architecture. Nothing there is directly portable.

`KALLSYMS_ALL` matters only to *their* design. Our manual-hook build resolves `_raw_spin_lock_irq` and
`seccomp_filter_release` (both **text** symbols) via `infra/symbol_resolver.c`; `sys_call_table` is only needed by
`hook/syscall_table_hook.c`, which `CONFIG_KSU_TAMPER_SYSCALL_TABLE` does not enable in our config. So the
"we need `KALLSYMS_ALL` too" concern raised earlier is **closed — not applicable to our configuration**.

---

## 4. Findings

Severity is about *impact if true*, not about confidence — each item states its own evidence.

### F1 — Their defconfig cannot bring up the display (theirs, **critical**, static)

Chain of evidence:

1. `arch/arm64/configs/vendor/xiaomi/miatoll_defconfig` is 794 lines (`695 =y`, `56 is not set`) and contains
   `CONFIG_DRM=y` (:456), `CONFIG_DRM_SDE_RSC=y` (:457), `CONFIG_FB_ARMCLCD=y` (:459) — but **no `CONFIG_DRM_MSM`**.
2. `drivers/gpu/drm/msm/Kconfig:2-14` defines `DRM_MSM` with dependencies and **no `default`** ⇒ `n`.
3. `config DRM_SDE_RSC` sits behind `depends on DRM_MSM` (`drivers/gpu/drm/msm/Kconfig:191-193`), so their own
   `CONFIG_DRM_SDE_RSC=y` is dropped by `olddefconfig` too.
4. `build.sh:84-85` applies that file directly (`make ... $DEFCONFIG; make ... olddefconfig`) and the CI does the
   same (`DEFCONFIG: vendor/xiaomi/miatoll_defconfig`), with **no fragment merge** — unlike our
   `scripts/merge-defconfig.sh` over 17 fragments.

⇒ A kernel built from the repo as committed has no MSM display driver: no panel, no framebuffer, black screen.
`CONFIG_QCOM_KGSL`, `SCSI_UFS_QCOM` and `QCA_CLD_WLAN` are present, so this is specifically the display stack.

*Caveat:* their published `Saamrox-20261007` zips may have been built from a different config than the one in git.
Either way the repo's own path is broken, and their defconfig must not be used as a feature reference.

### F2 — Our SUSFS AVC-log spoofing is compiled out (ours, **high**, verified in source)

- `arch/arm64/configs/vendor/xiaomi/miatoll_defconfig:59` → `# CONFIG_AUDIT is not set`.
- In 4.14, `security/selinux/Kconfig` does **not** `select AUDIT` (only `security/apparmor/Kconfig:4` does), and
  AppArmor is not enabled in our config. `CONFIG_AUDIT_ARCH_COMPAT_GENERIC=y` (:5859) is an arch capability,
  not the audit core.
- Our spoof lives in `security/selinux/avc.c:779-781`, inside `avc_audit_post_callback()`, which is inside
  `#ifdef CONFIG_AUDIT` (:739).

⇒ With the shipped config the whole block — spoof, `permissive=` field, `sad.denied` — is dead code, and the kernel
emits **no `avc:` records at all**. Their tree has no `CONFIG_AUDIT` line either, so its audit core is off by
default as well (`init/Kconfig:309` has no `default y` in their tree); their spoof is equally inert.

This does not weaken hiding (an absent log cannot leak), but it does mean our feature ledger has been overstating
"AVC spoofing = active". Two honest options:

- **A** — enable `CONFIG_AUDIT=y` (needs only `NET`): spoof becomes live, and SELinux denial logging returns.
- **B** — keep audit off, delete the spoof block and the claim. Saves ~1 KB and removes dead code.

If A is chosen, **our implementation is already the safe one** (see F4): it substitutes a local `u32 tsid` and calls
`avc_dump_query()` once — no control-flow jump, no leak, and no mutation of the shared `common_audit_data`.

### F3 — `/proc/kallsyms` denylist is far too narrow (ours, **high**, live)

Our filter (`kernel/kallsyms.c:607-611`) covers five prefixes: `ksu_`, `__ksu_`, `susfs_`, `ksud`, `is_ksu_`.
It is live (`CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y`, `kernel/configs/miatoll/susfs.config:11`).

`/proc/kallsyms` prints **names to every user**; only the address is gated by `%pK`. Twelve symbol families that
exist as real globals in our tree are therefore visible to any app that reads the file:

| visible symbol | defined at |
|---|---|
| `escape_to_root_for_init` / `escape_to_root_for_adb_root` | `KernelSU-Next/kernel/core/init.c:168`, `feature/adb_root.c:177` |
| `is_manager_apk` | `KernelSU-Next/kernel/manager/apk_sign.c:367` |
| `track_throne` | `KernelSU-Next/kernel/core/init.c:180`, `hook/lsm_hooks.c:94` |
| `handle_sepolicy` | `KernelSU-Next/kernel/selinux/rules.c:542` |
| `try_umount` | `KernelSU-Next/kernel/feature/kernel_umount.c:85` |
| `setup_selinux` | `KernelSU-Next/kernel/policy/app_profile.c:225` |
| plus `kernelsu*`, `on_post_fs_data*`, `apply_kernelsu*`, `getenforce*`, `setenforce*`, `is_zygote*` | matched in `KernelSU-Next/kernel/**` |

Their list (`kernel/kallsyms.c:615-648`) covers all of these. That is the one thing in their tree worth taking —
but transcribed by hand, not copied (our names differ; see Appendix C, patch 1).

### F4 — Their AVC spoof leaks `scontext` (theirs, **medium**, latent)

`security/selinux/avc.c` on branch 17:

```
194  rc = security_sid_to_context(state, tsid, &scontext, &scontext_len);
196  #ifdef CONFIG_KSU_SUSFS
197      if (static_branch_likely(&susfs_is_avc_log_spoofing_enabled)) {
198          if (unlikely(tsid == susfs_ksu_sid)) {
199              if (rc)     audit_log_format(ab, " tsid=%d", susfs_priv_app_sid);
201              else        audit_log_format(ab, " tcontext=%s", "u:r:priv_app:s0:c512,c768");
203              goto bypass_orig_flow;
...
208  if (rc) audit_log_format(ab, " tsid=%d", tsid);
210  else { audit_log_format(ab, " tcontext=%s", scontext);
212         kfree(scontext); }
216  bypass_orig_flow:
```

`security_sid_to_context()` allocates (`kstrdup` at `ss/services.c:1239`, `kmalloc` at `:1256`). On the spoof path
with `rc == 0` — the normal case, because the KSU SID resolves — line 203 jumps over the only `kfree()` at 212.
Every spoofed AVC record leaks one context string. Latent today only because their audit core is off (F2);
enable `CONFIG_AUDIT` and it becomes an unbounded kmalloc leak in a hot path.

Two more defects in the same block: the replacement context is **hardcoded** (it will be wrong on any policy whose
`priv_app` differs in categories), and `susfs_priv_app_sid` is never checked for 0. Ours does neither.

### F5 — GENI UART: we keep the pre-fix predicate (ours, **medium**)

`drivers/tty/serial/msm_geni_serial.c:470-473`:

```c
static bool device_pending_suspend(struct uart_port *uport)
{
    int usage_count = atomic_read(&uport->dev->power.usage_count);
    return (pm_runtime_status_suspended(uport->dev) || !usage_count);   /* ours: || */
}
```

`AzyrRuthless@16:470`, Kinesis `17:470` and **LineageOS `lineage-22.2:470`** all use `&&`;
LineageOS `lineage-20:470` still had `||`. So this is an upstream fix that landed after our base was cut.
Effect: with `||`, every caller (`break_ctl`, `get/set_mctrl`, `stop_tx`, `start/stop_rx`, `tx_empty`) bails out
whenever **nobody holds a runtime-PM reference**, even while the port is running — TX sequencer teardown and RX
setup are skipped. Console traffic is unaffected (`!uart_console(uport)` guards every call), so this is not the
boot-logo hang; it is a latent serial/BT-UART reliability bug.

### F6 — `BUG()` in the policy parser (ours, **medium**, hardening)

`security/selinux/ss/services.c:967` and `:1004` still `BUG()` on an unknown extended-permission block or unknown
`specified` key — reachable from `security_load_policy()`. Kinesis replaced both with
`pr_warn_once(...) + return` (their `ss/services.c` @@ -964 and @@ -1001 hunks), matching the upstream hardening.
A malformed policy should not panic the device.

### F7 — They removed every `CONFIG_AUDIT` guard (theirs, **low**)

`security/selinux/{avc.c, include/avc.h, hooks.c}`, `ss/services.c` `aurule_*`: their tree no longer has the
`#ifdef CONFIG_AUDIT` structure that stock 4.14 uses. It still compiles at `AUDIT=n` because `include/linux/audit.h`
supplies stubs, but it makes the file structurally divergent from upstream for no gain. Our tree keeps the guards.

### F8 — Their `BUG()` → `pr_warn_once()` is the right direction (theirs, take it)

Covered by F6. Two-line change, no downside.

### F9 — `simple_lmk.h` is dead code, not a feature (theirs, **info**)

`include/linux/simple_lmk.h` exists only in their tree, but there is **no `mm/simple_lmk.c`** and nothing includes
the header. It is a leftover from the base fork. Do not chase it.

### F10 — Their kernel `Makefile` is untouched (theirs, **info**)

`git log -- Makefile` on branch 17 shows only LTS commits. All of their clang-22 warning relaxation lives in
`build.sh` as `KCFLAGS` (`-Wno-error=unknown-warning-option`, `implicit-int`, `implicit-function-declaration`,
`strict-prototypes`, `incompatible-pointer-types`, `designated-init`, `date-time`). If we ever need those flags,
they are a `KCFLAGS` line, not a Makefile patch.

---

## 5. Feature matrix

| Capability | Stormbreaker | Kinesis 17 | Note |
|---|---|---|---|
| LTO / Polly / ThinLTO | yes | yes | same approach |
| SUSFS 2.3.0 (9 features) | yes | yes | ours is an independent implementation |
| NoMount | **v21** | v20 | yours is newer |
| `/proc/kallsyms` symbol hiding | 5 prefixes | **20 prefixes** | F3 — take theirs |
| AVC-log spoof | implemented, **inert** (F2) | implemented, inert (F2) | ours is leak-free (F4) |
| process reclaim (`/proc/pid/reclaim`) | **yes** (`CONFIG_PROCESS_RECLAIM=y`, defconfig:621) | no | ours only |
| extra perf counters | **yes** (`arch/arm64/kernel/perf_trace_*.c`) | no | ours only |
| NTFS3 | **yes** (`fs/ntfs3/`) | no | ours only |
| config fragments (17 files) | **yes** (`kernel/configs/miatoll/`) | no | ours only |
| AW8624 haptics | yes | yes (ported 2026-10-07) | theirs is a later port; not compared functionally |
| Zip installer | `BLOCK=/dev/block/bootdevice/by-name/boot`, `do.cleanuponabort=1` | `BLOCK=boot`, `do.cleanuponabort=0` | ours is correct for this AK3 (`tools/ak3-core.sh:944` accepts only `/dev/*`) |

---

## 6. Where our tree is ahead (evidence)

1. **AVC spoof implementation** — local `u32 tsid` substitution, zero-SID guards, no control-flow jump,
   `avc_dump_query()` does the alloc/free itself (`security/selinux/avc.c:779-786`). Theirs leaks (F4).
2. **Scheduler core content** — ours carries post-CAF upstream fixes theirs lacks: `hrtimer_set_expires()` in
   `hrtick_start()` (ours `kernel/sched/core.c:304-320` vs their `rq->hrtick_time`), and
   `nr_uninterruptible` accounting in `activate_task()/deactivate_task()` (ours `core.c:805-812`). Theirs is the
   older CAF variant plus tuning values (5 ms latency, 500 µs min-granularity, `child_runs_first=1`,
   `capacity_margin_up=1735` / `down=2844`, `nr_migrate=NR_CPUS`).
3. **kallsyms type correctness** — ours keeps 4.14's `unsigned long kallsyms_num_syms[]` with `PTR` emission
   (`scripts/kallsyms.c:459`); theirs switched to `unsigned int` + `.long %u` (`:481`). Their change is
   self-consistent, but ours matches the rest of the 4.14 tooling and any external parser.
4. **`arch/arm64/kernel/io.c`** — ours has the dual `IS_ALIGNED(from, 8) && IS_ALIGNED(to, 8)` fix and `volatile`
   casts; theirs does not.
5. **`arch/arm64/kernel/cpufeature.c`** — ours applies Cortex-A55 erratum 1024718 with
   `MIDR_RANGE(MIDR_CORTEX_A55, 0, 0, 1, 0)`; theirs uses `MIDR_ALL_VERSIONS()`, i.e. wider than the erratum.
6. **`arch/arm64/kernel/smp.c`** — ours keeps `soc/qcom/lpm_levels.h`, uses `pr_debug`, and guards
   `arch_send_wakeup_ipi_mask()` behind `CONFIG_ARM64_ACPI_PARKING_PROTOCOL`; theirs drops all three.
7. **Installer** — our `BLOCK` form is the one this AK3 accepts; theirs had to be fixed in `c5408bac8` precisely
   because `BLOCK=boot` resolved to nothing. We also keep `do.cleanuponabort=1`; theirs turned it off.

## 7. Where they are ahead

1. **kallsyms denylist breadth** (F3) — the only substantive thing to port.
2. **`pr_warn_once()` instead of `BUG()`** in the extended-permission validator (F6/F8).
3. **`policydb.c` android-netlink flags** — their `policydb_write_settings()` also writes
   `POLICYDB_CONFIG_ANDROID_NETLINK_ROUTE` / `_GETNEIGH` back into the serialized policy
   (`ss/policydb.c` @@ -3475). Four lines; affects what `security_read_policy()` reports, not enforcement.
4. **`susfs_fake_cmdline_or_bootconfig_seqlock`** — their cmdline spoof uses a seqlock shadow buffer; ours rewrites
   the buffer once at init under a mutex. Both are correct for a read-only `/proc/cmdline`; no action, noted for
   completeness.
5. **Haptics driver** — their `3d955e5d8` ports a maintained AW8624 driver; ours has its own. Not functionally
   compared (outside the audited directories).

---

## 8. Ledger

| # | Item | Side | Status |
|---|---|---|---|
| F1 | defconfig has no `DRM_MSM` | theirs | **static-verified**, no action for us |
| F2 | `CONFIG_AUDIT=n` disables our AVC spoof | ours | **verified in source**; decision required (A/B) |
| F3 | kallsyms denylist too narrow | ours | **verified**, patch ready (Appendix C) |
| F4 | AVC spoof leaks `scontext` | theirs | **verified in source**, latent at `AUDIT=n` |
| F5 | GENI `\|\|` vs `&&` | ours | **verified** against LineageOS 20/22.2 |
| F6 | `BUG()` in `services.c:967,1004` | ours | **verified**, patch ready |
| F7 | `CONFIG_AUDIT` guards removed | theirs | verified, no action |
| F9 | `simple_lmk.h` dead | theirs | verified, ignore |
| F10 | Makefile untouched, `KCFLAGS` only | theirs | verified, no action |
| — | `KEEP(*(.altinstr_replacement))` | — | **closed dead end**: `--gc-sections` is only added under `CONFIG_LD_DEAD_CODE_DATA_ELIMINATION` (`Makefile:1121-1124`), which neither tree sets ⇒ `KEEP()` is a no-op. Not the boot-logo cause. |
| — | `KALLSYMS_ALL` gap | ours | **closed**: manual hook needs only text symbols |
| — | kallsyms marker width | ours | **closed**: ours matches 4.14 |

---

## 9. Recommended sequence

1. Decide F2. If **A** (enable `CONFIG_AUDIT`), ship it as its own build and re-check log volume before publishing.
2. Land F3, F6, F5 as one small commit each — they are independent and low-risk.
3. Leave their defconfig, root driver and installer alone.
4. Optional, cosmetic: F8 (`pr_warn_once`) and the `policydb.c` flags.

**Do not push these yet:** `build.yml` uses `concurrency: cancel-in-progress: true`
(`.github/workflows/build.yml:54-56`), so any push cancels the still-running build 185
(`39644495181`, A17 tracing pack) and its `ci-logs/` evidence.

---

## Appendix A — full file ledger

### A.1 — the seven audited directories (327 entries)

`root-stack hook` = the diff is SUSFS/KernelSU/NoMount integration; `base lineage` = upstream/vendor divergence
(scheduler, LTS, QCOM drivers); `KSU variant` = different root driver, not comparable line-for-line.

| file | verdict | lines |
|---|---|---|
| `fs/Makefile` | root-stack hook | 2+/1- |
| `fs/exec.c` | root-stack hook | 0+/35- |
| `fs/namei.c` | root-stack hook | 190+/111- |
| `fs/namespace.c` | root-stack hook | 111+/177- |
| `fs/nomount/Makefile` | root-stack hook | 2+/18- |
| `fs/nomount/nomount.c` | root-stack hook | 821+/1247- |
| `fs/nomount/nomount.h` | root-stack hook | 94+/212- |
| `fs/notify/fdinfo.c` | root-stack hook | 55+/49- |
| `fs/open.c` | root-stack hook | 19+/72- |
| `fs/proc/base.c` | root-stack hook | 8+/7- |
| `fs/proc/cmdline.c` | root-stack hook | 6+/5- |
| `fs/proc/fd.c` | root-stack hook | 48+/52- |
| `fs/proc/task_mmu.c` | root-stack hook | 203+/131- |
| `fs/proc/version.c` | root-stack hook | 3+/22- |
| `fs/proc_namespace.c` | root-stack hook | 173+/16- |
| `fs/read_write.c` | root-stack hook | 0+/12- |
| `fs/readdir.c` | root-stack hook | 166+/107- |
| `fs/stat.c` | root-stack hook | 49+/48- |
| `fs/statfs.c` | root-stack hook | 25+/34- |
| `fs/super.c` | root-stack hook | 23+/21- |
| `fs/susfs.c` | root-stack hook | 92+/357- |
| `include/linux/susfs.h` | root-stack hook | 1+/24- |
| `include/linux/susfs_def.h` | root-stack hook | 67+/11- |
| `kernel/kallsyms.c` | root-stack hook | 34+/14- |
| `kernel/reboot.c` | root-stack hook | 3+/23- |
| `kernel/sys.c` | root-stack hook | 8+/15- |
| `kernel/utsname_sysctl.c` | root-stack hook | 0+/19- |
| `mm/memory.c` | root-stack hook | 8+/16- |
| `security/selinux/avc.c` | root-stack hook | 29+/40- |
| `arch/arm64/kernel/Makefile` | base lineage | 1+/2- |
| `arch/arm64/kernel/cpu-reset.h` | base lineage | 1+/1- |
| `arch/arm64/kernel/cpu_errata.c` | base lineage | 2+/7- |
| `arch/arm64/kernel/cpufeature.c` | base lineage | 1+/2- |
| `arch/arm64/kernel/io.c` | base lineage | 5+/7- |
| `arch/arm64/kernel/smp.c` | base lineage | 2+/11- |
| `arch/arm64/kernel/vmlinux.lds.S` | base lineage | 1+/1- |
| `fs/Kconfig` | base lineage | 0+/1- |
| `fs/block_dev.c` | base lineage | 2+/2- |
| `fs/buffer.c` | base lineage | 10+/50- |
| `fs/crypto/policy.c` | base lineage | 1+/1- |
| `fs/dcache.c` | base lineage | 60+/13- |
| `fs/drop_caches.c` | base lineage | 14+/8- |
| `fs/erofs/zdata.c` | base lineage | 1+/1- |
| `fs/ext4/ext4.h` | base lineage | 1+/0- |
| `fs/ext4/inline.c` | base lineage | 14+/0- |
| `fs/ext4/inode.c` | base lineage | 54+/0- |
| `fs/ext4/readpage.c` | base lineage | 43+/4- |
| `fs/ext4/super.c` | base lineage | 15+/26- |
| `fs/ext4/xattr_security.c` | base lineage | 6+/2- |
| `fs/f2fs/Makefile` | base lineage | 6+/0- |
| `fs/f2fs/acl.c` | base lineage | 22+/1- |
| `fs/f2fs/f2fs.h` | base lineage | 3+/1- |
| `fs/f2fs/file.c` | base lineage | 7+/2- |
| `fs/f2fs/segment.h` | base lineage | 2+/2- |
| `fs/f2fs/super.c` | base lineage | 0+/22- |
| `fs/f2fs/xattr.c` | base lineage | 20+/7- |
| `fs/fcntl.c` | base lineage | 4+/10- |
| `fs/file_table.c` | base lineage | 0+/52- |
| `fs/mbcache.c` | base lineage | 57+/24- |
| `fs/nfs/nfs4xdr.c` | base lineage | 16+/30- |
| `fs/nfsd/nfs3xdr.c` | base lineage | 11+/36- |
| `fs/nfsd/nfs4callback.c` | base lineage | 2+/2- |
| `fs/nfsd/nfs4xdr.c` | base lineage | 1+/1- |
| `fs/nfsd/nfsfh.h` | base lineage | 24+/8- |
| `fs/ntfs/aops.c` | base lineage | 1+/1- |
| `fs/ntfs/mft.c` | base lineage | 1+/1- |
| `fs/overlayfs/super.c` | base lineage | 4+/4- |
| `fs/proc/internal.h` | base lineage | 1+/0- |
| `fs/pstore/Kconfig` | base lineage | 55+/22- |
| `fs/pstore/inode.c` | base lineage | 4+/2- |
| `fs/pstore/internal.h` | base lineage | 3+/0- |
| `fs/pstore/platform.c` | base lineage | 67+/42- |
| `fs/pstore/ram.c` | base lineage | 76+/48- |
| `fs/sdcardfs/derived_perm.c` | base lineage | 2+/2- |
| `fs/sdcardfs/lookup.c` | base lineage | 1+/1- |
| `fs/sdcardfs/main.c` | base lineage | 13+/13- |
| `fs/sdcardfs/packagelist.c` | base lineage | 4+/4- |
| `fs/sdcardfs/super.c` | base lineage | 1+/1- |
| `fs/userfaultfd.c` | base lineage | 4+/1- |
| `include/linux/audit.h` | base lineage | 1+/1- |
| `include/linux/blk-mq.h` | base lineage | 2+/2- |
| `include/linux/blk_types.h` | base lineage | 0+/6- |
| `include/linux/blkdev.h` | base lineage | 6+/10- |
| `include/linux/buffer_head.h` | base lineage | 1+/1- |
| `include/linux/cgroup-defs.h` | base lineage | 1+/1- |
| `include/linux/cgroup.h` | base lineage | 3+/12- |
| `include/linux/clk.h` | base lineage | 1+/1- |
| `include/linux/cpuidle.h` | base lineage | 10+/0- |
| `include/linux/cpumask.h` | base lineage | 4+/0- |
| `include/linux/dcache.h` | base lineage | 1+/0- |
| `include/linux/dma-buf.h` | base lineage | 2+/0- |
| `include/linux/file.h` | base lineage | 0+/5- |
| `include/linux/fs.h` | base lineage | 4+/1- |
| `include/linux/genhd.h` | base lineage | 1+/0- |
| `include/linux/i2c.h` | base lineage | 0+/1- |
| `include/linux/interrupt.h` | base lineage | 6+/0- |
| `include/linux/irq.h` | base lineage | 2+/0- |
| `include/linux/kallsyms.h` | base lineage | 1+/1- |
| `include/linux/kmsg_dump.h` | base lineage | 2+/3- |
| `include/linux/kthread.h` | base lineage | 19+/0- |
| `include/linux/lz4.h` | base lineage | 2+/3- |
| `include/linux/mm.h` | base lineage | 14+/15- |
| `include/linux/msm_gsi.h` | base lineage | 2+/2- |
| `include/linux/netdevice.h` | base lineage | 11+/14- |
| `include/linux/oom.h` | base lineage | 4+/4- |
| `include/linux/pageblock-flags.h` | base lineage | 1+/1- |
| `include/linux/pagemap.h` | base lineage | 11+/11- |
| `include/linux/pci.h` | base lineage | 4+/0- |
| `include/linux/percpu-refcount.h` | base lineage | 10+/17- |
| `include/linux/perf_event.h` | base lineage | 0+/9- |
| `include/linux/phy/phy.h` | base lineage | 1+/0- |
| `include/linux/posix-timers.h` | base lineage | 19+/6- |
| `include/linux/power_supply.h` | base lineage | 3+/6- |
| `include/linux/printk.h` | base lineage | 1+/1- |
| `include/linux/profile.h` | base lineage | 6+/17- |
| `include/linux/pstore.h` | base lineage | 7+/0- |
| `include/linux/pstore_ram.h` | base lineage | 1+/1- |
| `include/linux/sched.h` | base lineage | 33+/10- |
| `include/linux/sched/sysctl.h` | base lineage | 4+/2- |
| `include/linux/swait.h` | base lineage | 6+/5- |
| `include/linux/sync_file.h` | base lineage | 0+/9- |
| `include/linux/thermal.h` | base lineage | 6+/6- |
| `include/linux/time32.h` | base lineage | 15+/3- |
| `include/linux/time64.h` | base lineage | 7+/0- |
| `include/linux/timekeeping.h` | base lineage | 14+/37- |
| `include/linux/timekeeping32.h` | base lineage | 59+/11- |
| `include/linux/usb/usbnet.h` | base lineage | 2+/3- |
| `include/linux/vmpressure.h` | base lineage | 9+/2- |
| `include/linux/wait.h` | base lineage | 10+/6- |
| `kernel/Makefile` | base lineage | 2+/2- |
| `kernel/bpf/core.c` | base lineage | 0+/6- |
| `kernel/cgroup/Makefile` | base lineage | 6+/0- |
| `kernel/cgroup/cgroup-internal.h` | base lineage | 1+/1- |
| `kernel/cgroup/cgroup-v1.c` | base lineage | 26+/46- |
| `kernel/cgroup/cgroup.c` | base lineage | 52+/97- |
| `kernel/cpu.c` | base lineage | 32+/4- |
| `kernel/events/core.c` | base lineage | 133+/224- |
| `kernel/exit.c` | base lineage | 30+/0- |
| `kernel/fork.c` | base lineage | 3+/2- |
| `kernel/irq/Makefile` | base lineage | 5+/0- |
| `kernel/irq/chip.c` | base lineage | 4+/1- |
| `kernel/irq/cpuhotplug.c` | base lineage | 14+/2- |
| `kernel/irq/internals.h` | base lineage | 1+/0- |
| `kernel/irq/irqdesc.c` | base lineage | 1+/1- |
| `kernel/irq/manage.c` | base lineage | 172+/2- |
| `kernel/livepatch/core.c` | base lineage | 2+/2- |
| `kernel/module.c` | base lineage | 26+/1- |
| `kernel/panic.c` | base lineage | 2+/2- |
| `kernel/power/hibernate.c` | base lineage | 10+/0- |
| `kernel/power/process.c` | base lineage | 18+/8- |
| `kernel/power/qos.c` | base lineage | 5+/22- |
| `kernel/power/suspend.c` | base lineage | 36+/6- |
| `kernel/printk/printk.c` | base lineage | 12+/16- |
| `kernel/rcu/tree.c` | base lineage | 2+/1- |
| `kernel/rcu/tree_plugin.h` | base lineage | 2+/2- |
| `kernel/sched/autogroup.c` | base lineage | 1+/1- |
| `kernel/sched/boost.c` | base lineage | 1+/1- |
| `kernel/sched/cass.c` | base lineage | 1+/23- |
| `kernel/sched/core.c` | base lineage | 459+/99- |
| `kernel/sched/core_ctl.c` | base lineage | 4+/0- |
| `kernel/sched/cpufreq_schedutil.c` | base lineage | 75+/259- |
| `kernel/sched/cpupri.c` | base lineage | 1+/1- |
| `kernel/sched/energy.c` | base lineage | 40+/56- |
| `kernel/sched/fair.c` | base lineage | 252+/123- |
| `kernel/sched/features.h` | base lineage | 11+/9- |
| `kernel/sched/idle.c` | base lineage | 12+/5- |
| `kernel/sched/rt.c` | base lineage | 37+/9- |
| `kernel/sched/sched.h` | base lineage | 56+/52- |
| `kernel/sched/swait.c` | base lineage | 17+/5- |
| `kernel/sched/topology.c` | base lineage | 2+/2- |
| `kernel/sched/tune.c` | base lineage | 1+/1- |
| `kernel/sched/wait.c` | base lineage | 27+/3- |
| `kernel/sched/walt.c` | base lineage | 16+/39- |
| `kernel/signal.c` | base lineage | 3+/7- |
| `kernel/smp.c` | base lineage | 15+/1- |
| `kernel/softirq.c` | base lineage | 19+/1- |
| `kernel/sysctl.c` | base lineage | 48+/18- |
| `kernel/time/hrtimer.c` | base lineage | 1+/0- |
| `kernel/time/ntp.c` | base lineage | 1+/1- |
| `kernel/time/posix-clock.c` | base lineage | 1+/1- |
| `kernel/time/posix-cpu-timers.c` | base lineage | 2+/2- |
| `kernel/time/sched_clock.c` | base lineage | 0+/10- |
| `kernel/time/tick-common.c` | base lineage | 16+/5- |
| `kernel/time/time.c` | base lineage | 2+/0- |
| `kernel/time/timekeeping.c` | base lineage | 39+/15- |
| `kernel/trace/Kconfig` | base lineage | 4+/3- |
| `kernel/trace/trace_event_perf.c` | base lineage | 1+/0- |
| `kernel/trace/trace_printk.c` | base lineage | 1+/1- |
| `kernel/workqueue.c` | base lineage | 1+/1- |
| `mm/Kconfig` | base lineage | 72+/0- |
| `mm/Makefile` | base lineage | 0+/1- |
| `mm/filemap.c` | base lineage | 6+/6- |
| `mm/gup.c` | base lineage | 1+/1- |
| `mm/huge_memory.c` | base lineage | 1+/2- |
| `mm/internal.h` | base lineage | 1+/0- |
| `mm/khugepaged.c` | base lineage | 1+/6- |
| `mm/kmemleak.c` | base lineage | 4+/5- |
| `mm/ksm.c` | base lineage | 3+/3- |
| `mm/mempolicy.c` | base lineage | 1+/2- |
| `mm/mmap.c` | base lineage | 6+/13- |
| `mm/oom_kill.c` | base lineage | 15+/60- |
| `mm/page-writeback.c` | base lineage | 3+/3- |
| `mm/page_alloc.c` | base lineage | 56+/15- |
| `mm/slab_common.c` | base lineage | 3+/0- |
| `mm/slub.c` | base lineage | 13+/12- |
| `mm/swap.c` | base lineage | 3+/0- |
| `mm/util.c` | base lineage | 2+/2- |
| `mm/vmpressure.c` | base lineage | 132+/101- |
| `mm/vmscan.c` | base lineage | 165+/21- |
| `mm/zsmalloc.c` | base lineage | 11+/5- |
| `security/Kconfig` | base lineage | 0+/3- |
| `security/selinux/hooks.c` | base lineage | 0+/2- |
| `security/selinux/include/avc.h` | base lineage | 0+/4- |
| `security/selinux/ss/policydb.c` | base lineage | 4+/0- |
| `security/selinux/ss/services.c` | base lineage | 6+/4- |
| `security/smack/smack_lsm.c` | base lineage | 2+/2- |
| `drivers/kernelsu/Kconfig` | KSU variant (differs by design) | 121+/87- |
| `drivers/kernelsu/Makefile` | KSU variant (differs by design) | 162+/19- |
| `drivers/kernelsu/feature/adb_root.c` | KSU variant (differs by design) | 283+/211- |
| `drivers/kernelsu/feature/adb_root.h` | KSU variant (differs by design) | 3+/6- |
| `drivers/kernelsu/feature/kernel_umount.c` | KSU variant (differs by design) | 48+/103- |
| `drivers/kernelsu/feature/kernel_umount.h` | KSU variant (differs by design) | 0+/7- |
| `drivers/kernelsu/feature/selinux_hide.c` | KSU variant (differs by design) | 300+/582- |
| `drivers/kernelsu/feature/selinux_hide.h` | KSU variant (differs by design) | 253+/6- |
| `drivers/kernelsu/feature/sucompat.c` | KSU variant (differs by design) | 380+/203- |
| `drivers/kernelsu/feature/sucompat.h` | KSU variant (differs by design) | 1+/11- |
| `drivers/kernelsu/feature/sulog.c` | KSU variant (differs by design) | 35+/44- |
| `drivers/kernelsu/feature/sulog.h` | KSU variant (differs by design) | 2+/5- |
| `drivers/kernelsu/hook/setuid_hook.c` | KSU variant (differs by design) | 65+/152- |
| `drivers/kernelsu/include/arch.h` | KSU variant (differs by design) | 75+/20- |
| `drivers/kernelsu/include/klog.h` | KSU variant (differs by design) | 0+/8- |
| `drivers/kernelsu/include/ksu.h` | KSU variant (differs by design) | 10+/22- |
| `drivers/kernelsu/include/uapi/app_profile.h` | KSU variant (differs by design) | 39+/41- |
| `drivers/kernelsu/include/uapi/feature.h` | KSU variant (differs by design) | 6+/11- |
| `drivers/kernelsu/include/uapi/selinux.h` | KSU variant (differs by design) | 0+/2- |
| `drivers/kernelsu/include/uapi/sulog.h` | KSU variant (differs by design) | 14+/14- |
| `drivers/kernelsu/include/uapi/supercall.h` | KSU variant (differs by design) | 70+/117- |
| `drivers/kernelsu/include/util.h` | KSU variant (differs by design) | 73+/83- |
| `drivers/kernelsu/infra/event_queue.c` | KSU variant (differs by design) | 313+/345- |
| `drivers/kernelsu/infra/event_queue.h` | KSU variant (differs by design) | 28+/42- |
| `drivers/kernelsu/infra/file_wrapper.c` | KSU variant (differs by design) | 64+/276- |
| `drivers/kernelsu/infra/file_wrapper.h` | KSU variant (differs by design) | 0+/3- |
| `drivers/kernelsu/infra/su_mount_ns.c` | KSU variant (differs by design) | 137+/146- |
| `drivers/kernelsu/infra/su_mount_ns.h` | KSU variant (differs by design) | 0+/7- |
| `drivers/kernelsu/manager/apk_sign.c` | KSU variant (differs by design) | 91+/97- |
| `drivers/kernelsu/manager/apk_sign.h` | KSU variant (differs by design) | 1+/3- |
| `drivers/kernelsu/manager/manager_identity.h` | KSU variant (differs by design) | 4+/36- |
| `drivers/kernelsu/manager/pkg_observer.c` | KSU variant (differs by design) | 84+/181- |
| `drivers/kernelsu/manager/throne_tracker.c` | KSU variant (differs by design) | 162+/195- |
| `drivers/kernelsu/manager/throne_tracker.h` | KSU variant (differs by design) | 49+/15- |
| `drivers/kernelsu/policy/allowlist.c` | KSU variant (differs by design) | 293+/439- |
| `drivers/kernelsu/policy/allowlist.h` | KSU variant (differs by design) | 6+/18- |
| `drivers/kernelsu/policy/app_profile.c` | KSU variant (differs by design) | 151+/243- |
| `drivers/kernelsu/policy/app_profile.h` | KSU variant (differs by design) | 12+/8- |
| `drivers/kernelsu/policy/feature.c` | KSU variant (differs by design) | 7+/140- |
| `drivers/kernelsu/policy/feature.h` | KSU variant (differs by design) | 0+/12- |
| `drivers/kernelsu/runtime/ksud.h` | KSU variant (differs by design) | 15+/35- |
| `drivers/kernelsu/selinux/rules.c` | KSU variant (differs by design) | 395+/459- |
| `drivers/kernelsu/selinux/selinux.c` | KSU variant (differs by design) | 202+/235- |
| `drivers/kernelsu/selinux/selinux.h` | KSU variant (differs by design) | 15+/32- |
| `drivers/kernelsu/selinux/sepolicy.c` | KSU variant (differs by design) | 927+/1334- |
| `drivers/kernelsu/selinux/sepolicy.h` | KSU variant (differs by design) | 17+/17- |
| `drivers/kernelsu/setup.sh` | KSU variant (differs by design) | 10+/15- |
| `drivers/kernelsu/sulog/event.c` | KSU variant (differs by design) | 192+/441- |
| `drivers/kernelsu/sulog/event.h` | KSU variant (differs by design) | 28+/22- |
| `drivers/kernelsu/sulog/fd.c` | KSU variant (differs by design) | 52+/65- |
| `drivers/kernelsu/sulog/fd.h` | KSU variant (differs by design) | 2+/4- |
| `drivers/kernelsu/supercall/dispatch.c` | KSU variant (differs by design) | 368+/733- |
| `drivers/kernelsu/supercall/internal.h` | KSU variant (differs by design) | 1+/8- |
| `drivers/kernelsu/supercall/perm.c` | KSU variant (differs by design) | 3+/10- |
| `drivers/kernelsu/supercall/supercall.c` | KSU variant (differs by design) | 78+/311- |
| `drivers/kernelsu/supercall/supercall.h` | KSU variant (differs by design) | 7+/10- |
| `arch/arm64/kernel/perf_trace_counters.c` | ours only | - |
| `arch/arm64/kernel/perf_trace_counters.h` | ours only | - |
| `arch/arm64/kernel/perf_trace_user.c` | ours only | - |
| `arch/arm64/kernel/perf_trace_user.h` | ours only | - |
| `drivers/kernelsu/.clang-format` | ours only | - |
| `drivers/kernelsu/.clangd` | ours only | - |
| `drivers/kernelsu/.gitignore` | ours only | - |
| `drivers/kernelsu/.vscode` | ours only | - |
| `drivers/kernelsu/Kbuild` | ours only | - |
| `drivers/kernelsu/compat` | ours only | - |
| `drivers/kernelsu/core` | ours only | - |
| `drivers/kernelsu/extras.c` | ours only | - |
| `drivers/kernelsu/feature/shell_su_adb_only.c` | ours only | - |
| `drivers/kernelsu/feature/shell_su_adb_only.h` | ours only | - |
| `drivers/kernelsu/hook/hook_manager.c` | ours only | - |
| `drivers/kernelsu/hook/hook_manager.h` | ours only | - |
| `drivers/kernelsu/hook/lsm_hooks.c` | ours only | - |
| `drivers/kernelsu/hook/patch_memory.c` | ours only | - |
| `drivers/kernelsu/hook/patch_memory.h` | ours only | - |
| `drivers/kernelsu/hook/setuid_hook.h` | ours only | - |
| `drivers/kernelsu/hook/syscall_table_hook.c` | ours only | - |
| `drivers/kernelsu/hook/syscall_table_hook.h` | ours only | - |
| `drivers/kernelsu/include/uapi/ksu.h` | ours only | - |
| `drivers/kernelsu/infra/seccomp_cache.c` | ours only | - |
| `drivers/kernelsu/infra/seccomp_cache.h` | ours only | - |
| `drivers/kernelsu/infra/symbol_resolver.c` | ours only | - |
| `drivers/kernelsu/infra/symbol_resolver.h` | ours only | - |
| `drivers/kernelsu/manager/manager_observer.h` | ours only | - |
| `drivers/kernelsu/manager/pkg_observer_defs.h` | ours only | - |
| `drivers/kernelsu/preinit` | ours only | - |
| `drivers/kernelsu/runtime/boot_event.c` | ours only | - |
| `drivers/kernelsu/runtime/ksud_boot.h` | ours only | - |
| `drivers/kernelsu/runtime/ksud_integration.c` | ours only | - |
| `drivers/kernelsu/selinux/Makefile` | ours only | - |
| `drivers/kernelsu/tools` | ours only | - |
| `fs/ntfs3` | ours only | - |
| `include/linux/fiemap.h` | ours only | - |
| `kernel/configs/miatoll` | ours only | - |
| `mm/process_reclaim.c` | ours only | - |
| `drivers/kernelsu/INTERNAL.md` | theirs only | - |
| `drivers/kernelsu/downstream` | theirs only | - |
| `drivers/kernelsu/external` | theirs only | - |
| `drivers/kernelsu/hook/branch_link_hook_arm64.c` | theirs only | - |
| `drivers/kernelsu/hook/kp_ksud.c` | theirs only | - |
| `drivers/kernelsu/hook/lsm_hooks_list.c` | theirs only | - |
| `drivers/kernelsu/hook/lsm_hooks_manual.c` | theirs only | - |
| `drivers/kernelsu/hook/lsm_hooks_static.c` | theirs only | - |
| `drivers/kernelsu/hook/lsm_hooks_ultralegacy.c` | theirs only | - |
| `drivers/kernelsu/hook/syscall_table_hook_arm.c` | theirs only | - |
| `drivers/kernelsu/hook/syscall_table_hook_arm64.c` | theirs only | - |
| `drivers/kernelsu/kernel_compat.h` | theirs only | - |
| `drivers/kernelsu/kernel_includes.h` | theirs only | - |
| `drivers/kernelsu/ksu.c` | theirs only | - |
| `drivers/kernelsu/runtime/ksud.c` | theirs only | - |
| `include/linux/simple_lmk.h` | theirs only | - |

### A.2 — largest divergences outside the audited directories

| Δ bytes | file |
|---|---|
| 137,714 | `arch/arm64/configs/vendor/xiaomi/miatoll_defconfig` (5934 vs 794 lines) |
| 73,420 | `.elts/upstream/4.19.323.yaml` (ours only — ELTS 4.19 manifest) |
| 53,809 | `.elts/meta/4.14.356.yaml` |
| 35,447 | `drivers/net/wireguard/compat/compat.h` |
| 23,266 | `drivers/cpuidle/lpm-levels.c` |
| 15,784 | `drivers/staging/android/ashmem.c` |
| 11,570 | `drivers/scsi/ufs/ufs-qcom.c` |
| 10,842 | `drivers/power/supply/maxim/ds28e16.c` |
| 6,352 | `net/netfilter/nf_conntrack_irc.c` |
| 5,993 | `drivers/gpu/msm/kgsl_pwrscale.c` |
| 5,132 | `scripts/dtc/checks.c` |
| 5,109 | `drivers/gpu/msm/adreno.c` |

These are upstream/ELTS deltas; none touches the root stack.

---

## Appendix B — reproduce

```bash
git clone --depth 1 -b 17 https://github.com/Saamitk/Kinesis /tmp/kinesis17
cd /tmp/kinesis17 && git fetch --depth 1 origin 16:refs/remotes/origin/16
diff -rq  /path/to/Stormbreaker/{fs,kernel,mm,security} /tmp/kinesis17/{fs,kernel,mm,security}
diff -rq  /path/to/Stormbreaker/include/linux   /tmp/kinesis17/include/linux
diff -rq  /path/to/Stormbreaker/arch/arm64/kernel /tmp/kinesis17/arch/arm64/kernel
git diff --name-status origin/16 origin/17          # 113 A / 26 M
```

---

## Appendix C — patches (prepared, **not committed**)

**1. `kernel/kallsyms.c` — widen the denylist (F3).** Insert after the existing `is_ksu_` clause at
`kernel/kallsyms.c:611`, before the closing `)`:

```c
	    susfs_starts_with(iter->name, "is_manager_") ||
	    susfs_starts_with(iter->name, "escape_to_") ||
	    susfs_starts_with(iter->name, "setup_selinux") ||
	    susfs_starts_with(iter->name, "track_throne") ||
	    susfs_starts_with(iter->name, "on_post_fs_data") ||
	    susfs_starts_with(iter->name, "try_umount") ||
	    susfs_starts_with(iter->name, "kernelsu") ||
	    susfs_starts_with(iter->name, "apply_kernelsu") ||
	    susfs_starts_with(iter->name, "handle_sepolicy") ||
	    susfs_starts_with(iter->name, "getenforce") ||
	    susfs_starts_with(iter->name, "setenforce") ||
	    susfs_starts_with(iter->name, "is_zygote") ||
```

Each of these was confirmed to match at least one real symbol in `KernelSU-Next/kernel/**`; no `__initcall__kmod_*`
rule is proposed because our driver is not a module.

**2. `drivers/tty/serial/msm_geni_serial.c:473` — F5.**

```diff
-	return (pm_runtime_status_suspended(uport->dev) || !usage_count);
+	return (pm_runtime_status_suspended(uport->dev) && !usage_count);
```

**3. `security/selinux/ss/services.c:967` and `:1004` — F6.**

```diff
-		BUG();
+		pr_warn_once("SELinux: unknown extended permission (%u) will be ignored\n",
+			     node->datum.u.xperms->specified);
+		return;
```

and, at the second site,

```diff
-		BUG();
+		pr_warn_once("SELinux: unknown specified key (%u)\n",
+			     node->key.specified);
```
