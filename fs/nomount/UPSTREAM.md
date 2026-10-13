# NoMount provenance

- Upstream: https://github.com/maxsteeel/nomount
- Release: `v2.1.1` (tag `v2.1.1`, released 2026-10-13)
- Imported from: `kernel/src` (GPLv2)
- Integration: built in with `CONFIG_NOMOUNT=y` (tristate Kconfig kept, so
  an LKM build with `=m` is also possible)
- Companion userspace: the official metamodule
  `NoMount-v2.1.1-release-7046c7a-555.zip` from the same release; the CI
  workflow attaches it next to the kernel zip.

The upstream source is vendored rather than linked so kernel builds remain
reproducible and do not fetch or modify source during Kbuild.

v2.1.1 highlights (this tree now matches upstream `kernel/src` verbatim):

- Stability: UAF fixes in `d_revalidate`/`lookup`/`iterate_dir` (RCU +
  refs), OOB fix in `NM_CMD_GET_UIDS`, `pinned_dentry` cleanup in
  `nm_dir_rcu_free`, `fake_fop.owner = THIS_MODULE`, no `->evict_inode()`
  on virtual inodes.
- Performance: packed per-directory rule storage, hot-path lookup /
  iteration / revalidation pass, `call_rcu` deferred freeing (replaces the
  shared `synchronize_rcu` queue), one mutex per rule-add batch, scalable
  child bloom filters + UID-exclusion prefilter, `rcu_guard()` scope
  guards.
- 4.14/4.19 aware: xattr `__get` wrapper for SELinux + OverlayFS,
  `LINUX_VERSION_CODE` guards down to <4.11 with a 4.14..<5.4 key-payload
  path, so it compiles on 4.14.357.

## Local deviation from upstream v2.1.1

- `Makefile`: upstream's `NOMOUNT_COMMIT_COUNT` git-rev-list probe is
  removed (see the comment in the Makefile); `nm version` reports the base
  version. Upstream's LKM-oriented `-fno-stack-protector` is intentionally
  not carried: the in-tree build keeps the kernel's global stack-protector
  policy. `-O3` from upstream is kept.

Everything else is verbatim upstream v2.1.1.

### History

- v2.1.0 was imported first (with the post-release `7e7342cd4`
  virtual-inode `evict_inode` fix backported). That fix is part of the
  v2.1.1 tag, so the previous local delta is gone and `nomount.c` /
  `nomount.h` are now byte-identical to `maxsteeel/nomount@v2.1.1
  kernel/src`.
