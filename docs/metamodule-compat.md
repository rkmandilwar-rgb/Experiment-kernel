# KernelSU metamodules on this kernel

Notes for "metamodules make the phone stop at the boot logo with this kernel".
There are exactly two kernel-side reasons this can happen, and both were
verifiable in this tree rather than guessed at.

## 1. Module signing blocked every external module

Found in the configuration this kernel inherited from the vendor defconfig:

```
arch/arm64/configs/vendor/xiaomi/miatoll_defconfig (before)
  CONFIG_MODULE_SIG=y
  CONFIG_MODULE_SIG_FORCE=y
  CONFIG_MODULE_SIG_ALL=y
  CONFIG_MODULE_SIG_KEY="certs/signing_key.pem"
```

`MODULE_SIG_FORCE` means the kernel **refuses any module not signed with its
own key**. The key is `certs/signing_key.pem`, which `make` generates per build
if it does not exist — so it is unique to that checkout and no ROM module or
third-party module can ever be signed with it. In practice, on a kernel built
like this:

- the ROM's `/vendor/lib/modules/*.ko` are rejected,
- a metamodule's own kernel-module backend (Hybrid Mount's VFS provider, for
  example) is rejected,
- nothing outside the kernel image loads at all.

The Android 17 miatoll kernels that boot this ROM (`AbdoAhmedElbanaa/...@17`)
carry `CONFIG_MODULES=y` and `CONFIG_MODVERSIONS=y` and **no** `MODULE_SIG*`
option. That is the difference, and it is now matched:

```
arch/arm64/configs/vendor/xiaomi/miatoll_defconfig (after)
  CONFIG_MODVERSIONS=y
  # CONFIG_MODULE_SIG is not set
```

Unsigned modules now load (the kernel gets the usual `Tainted: G OE` flag,
which is expected and harmless).

Note that `CONFIG_LOCALVERSION="-Stormbreaker"` still makes the kernel's
`vermagic` differ from a ROM-built module's, so modules compiled against a
different tree are refused for that reason instead. That is normal for every
custom kernel on this device - the reference A17 kernel sets its own
`-BLACKHOLE-v4-Eclipse` localversion too - and it is why a metamodule cannot
rely on shipping a prebuilt `.ko` for this kernel.

## 2. NoMount and inode_operations-injecting metamodules cannot coexist

`fs/nomount/` works by replacing `inode->i_op` / `inode->i_fop` with its own
copies and remembering the originals (`fs/nomount/nomount.c:1005-1045`).
`nm_get_nm_iop()` identifies its own records by the function pointer inside the
operations vector:

```c
static inline struct nm_dir_ops *nm_get_nm_iop(const struct inode_operations *iop) {
    if (likely(iop) && iop->lookup == nomount_hijacked_lookup)
        return container_of(iop, struct nm_dir_ops, fake_iop);
    return NULL;
}
```

A metamodule backend that injects at the VFS layer does the same thing. When it
hijacks an inode **after** NoMount did, it saves NoMount's vector as its
"original" and the kernel starts calling *its* `->lookup`. That lookup chains
into `nomount_hijacked_lookup()`, where `dir->i_op` now points at the other
module's vector: `nm_get_nm_iop()` returns NULL, there is no recorded original
to fall back to, and the function ends at

```c
return ERR_PTR(-EOPNOTSUPP);
```

Every lookup under a hijacked directory then fails. `init` cannot read its
configuration, nothing mounts, and the device sits at the logo with no boot
animation. Since there is no correct return value available in that state, the
kernel now logs it once instead of failing silently:

```
NoMount: [WARN] lookup of '...' under ino N: inode ops owned by another
hijacker, cannot fall back
```

If you see that line, the two are fighting and one of them has to go.

## What to do

1. **Preferred: no metamodule.** Check whether the KernelSU-Next build in use
   mounts modules itself. KernelSU-Next does ship metamodule support
   (`userspace/ksud/src/metamodule.rs`), so a metamodule is legitimate - but an
   OverlayFS-only one (meta-overlayfs, MyOverlayFs) only needs userspace and
   `CONFIG_OVERLAY_FS`, both of which this kernel has. A hybrid one that can
   pick a VFS backend needs a loadable kernel module and cannot work here for
   the `vermagic` reason above; if it was configured with
   `vfs_strict = true`, that is a hard boot failure by design.
2. **If a metamodule must stay, keep it on the overlay backend.** In
   `config.toml` that is `default_mode = "overlay"` and no `vfs` rules.
3. **If the phone is already stuck**, recovery does not need this kernel:
   hold power until it reboots, then use KernelSU safe mode (volume key presses
   right after the first boot screen) or a recovery to remove
   `/data/adb/modules/<the metamodule>`.

## Reporting a hang

`dmesg` from a boot that reaches the logo is the deciding artefact:

- `module verification failed` / `Lockdown: ... module` - signing, i.e. the old
  build.
- `NoMount: [WARN] ... owned by another hijacker` - item 2 above.
- Nothing at all after the last subsystem line - init is blocked on something
  else and the metamodule is only the trigger, not the cause.
