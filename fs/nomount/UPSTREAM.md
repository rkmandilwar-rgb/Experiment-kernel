# NoMount provenance

- Upstream: https://github.com/maxsteeel/nomount
- Release: `v2.1.0` (tag `v2.1.0`, released 2026-10-06)
- Imported from: `kernel/src` (GPLv2)
- Integration: built in with `CONFIG_NOMOUNT=y` (tristate Kconfig kept, so
  an LKM build with `=m` is also possible)
- Companion userspace: the official metamodule
  `NoMount-v2.1.0-release-500.zip` from the same release; the CI workflow
  attaches it next to the kernel zip.

The upstream source is vendored rather than linked so kernel builds remain
reproducible and do not fetch or modify source during Kbuild.

v2.1.0 upstream notes relevant to this 4.14 non-GKI tree:

- kernel/ directory strictly GPLv2 (matches the kernel tree license).
- Fixes for SELinux + OverlayFS on kernels 4.14/4.19 (xattr `__get`
  wrapper), so this tag is explicitly 4.14-aware.
- Toggleable isolated-process blocking, leak fixes in directory hijacking,
  dropped heavy slab caches, native trusted.overlay.opaque whiteouts.
- The source carries `LINUX_VERSION_CODE` guards down through <4.11 and a
  dedicated 4.14..<5.4 path (key payload access), so it compiles on
  4.14.357.

## Local deviation from upstream v2.1.0

- Post-release upstream fix `7e7342cd4` (deref3046, merged in
  maxsteeel/nomount after the v2.1.0 tag) — "kernel: don't call
  ->evict_inode() if its a virtual inode": `nomount_hijacked_evict_inode()`
  must not invoke the real filesystem's `->evict_inode()` on NoMount's
  virtual inodes; it now routes them through
  `truncate_inode_pages_final()`/`clear_inode()` instead. Applied here
  because the same fix is required by other 4.14/5.10 in-kernel NoMount
  integrations.
- `Makefile`: upstream's `NOMOUNT_COMMIT_COUNT` git-rev-list probe removed
  (see the comment in the Makefile); `nm version` reports the base version.

Everything else is verbatim upstream v2.1.0.
