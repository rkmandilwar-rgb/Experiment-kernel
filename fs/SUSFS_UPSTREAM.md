# SUSFS provenance and compatibility

Current implementation: **SUSFS v2.3.0** — non-GKI Linux 4.14 semantic port.

## Provenance

- Upstream project: https://gitlab.com/simonpunk/susfs4ksu (GKI branches)
- Version-bump commit: `a64889c` ("fs: susfs: bump version to v2.3.0");
  upstream kernel changes by simonpunk/sidex15, Sep 12-13 2026.
- 4.14 semantic-port reference: https://github.com/star-star-dev/M62-backport
  pull request #3 (merged 2026-09-22), built from the same upstream commit
  series. Symbols unavailable on 4.14 (STATX_MNT_ID, zygote_next hooks,
  kstat.mnt_id) are omitted as no-ops, matching that reference.
- The userspace command ABI is bridged to the manually integrated Backslashxx
  KernelSU tree over the supercall channel; the old upstream KernelSU patch
  was not applied wholesale because it targets a different KernelSU layout
  and API.

## History

- The original import (early 2026-09) came from the upstream `kernel-4.14`
  branch (mirror: https://github.com/Star-Seven/susfs4ksu @ `d18028f`),
  which reported **v1.5.5**. That lineage predated BRENE's v2.2.0+
  requirement and is no longer present in this tree.
- Later 2026-09: replaced by the v2.3.0 semantic port described above, with
  local adaptations on top of the reference: NULL-safe sus_kstat fallbacks,
  get_anon_bdev() KSU hook adapted to the 4.14 ida API
  (ida_pre_get/ida_get_new_above), maps/fdinfo spoofing with v2.3.0 app-uid
  gating, and the upstream vfs_statfs f_flags fix (769e31fbe).

## Compatibility

- SUSFS v2.3.0 **meets and exceeds** BRENE's stated v2.2.0-or-newer
  requirement. BRENE v0.0.68 is fully compatible: its CMD_SUSFS_* command
  set (v2.3.0 dialect) is served by this tree over the KSU supercall
  channel, gated to root + KSU domain.
- Validated on real hardware (curtana, Infinity X, Android 16): susfs
  initializes at boot, BRENE rules apply, uname spoofing and sus mounts
  behave as configured.
