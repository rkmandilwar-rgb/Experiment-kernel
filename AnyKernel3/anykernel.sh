# AnyKernel3 Ramdisk Mod Script
# osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=Stormbreaker Kernel by rkmandilwar-rgb @ github
kernel.compiler=LLVM 22 (Clang/LLD)
kernel.made=CI/CD
kernel.version=4.14.357-openela-Stormbreaker
message.word=
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=1
device.name1=miatoll
device.name2=curtana
device.name3=gram
device.name4=joyeuse
device.name5=excalibur
supported.versions=10-17
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


# boot shell variables. Keep the names expected by this bundled AK3 core.
BLOCK=/dev/block/bootdevice/by-name/boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

########################################################################
# Stormbreaker install policy: replace the kernel image, nothing else.
#
#   Image.gz   the only thing this zip writes: it becomes the kernel of a
#              freshly repacked boot image.
#   DTB        kept byte for byte from the boot image being replaced.
#   dtbo       never written; the partition is left exactly as it is.
#   ramdisk, cmdline, base, page size, header revision
#              all inherited from the image being replaced.
#
# This is intentional.  The device tree describes the hardware (panel,
# touch, regulators, camera, CPR) and is matched to the ROM; this kernel is
# a drop-in for the same 4.14 tree, so the only thing worth changing is the
# kernel itself.  It makes the zip equally valid over a stock ROM and over a
# custom ROM, and it cannot leave boot and dtbo carrying device trees from
# two different builds.
#
# Mechanically this is split_boot + flash_boot.  flash_boot() writes the boot
# partition only; write_boot() -- the helper that would also flash dtbo -- is
# deliberately not called, and no dtb/dtbo.img ships in the archive, so
# nothing can override the existing device tree.
########################################################################

# Back up the current boot image next to the sdcard (or /data/media/0, or
# /tmp) and check the copy against the partition size.  This is the only
# recovery path a kernel-only zip needs: DTB and DTBO are not touched, so a
# working boot image is all that would ever have to be restored.
backup_boot() {
  local dir dst stamp size_bytes want_bytes

  for dir in /sdcard /data/media/0 /tmp; do
    [ -d "$dir" ] && break
    dir=
  done

  if [ ! "$dir" ]; then
    ui_print "[!] No writable storage found; skipping the boot backup.";
    return 1
  fi

  stamp=$(date +%Y%m%d-%H%M%S 2>/dev/null);
  [ "$stamp" ] || stamp=latest;
  dst="$dir/Stormbreaker-backup-$stamp";

  if ! mkdir -p "$dst" 2>/dev/null; then
    ui_print "[!] Cannot create $dst; skipping the boot backup.";
    return 1
  fi

  ui_print " ";
  ui_print "[+] Backing up the current boot image . . .";
  if ! dd if="$BLOCK" of="$dst/boot.img" bs=1048576 2>/dev/null; then
    rm -f "$dst/boot.img";
    ui_print "[!] Boot backup failed; continuing without one.";
    return 1
  fi

  size_bytes=$(wc -c < "$dst/boot.img" 2>/dev/null);
  want_bytes=$(blockdev --getsize64 "$BLOCK" 2>/dev/null);
  if [ "$want_bytes" ] && [ "$size_bytes" != "$want_bytes" ]; then
    ui_print "[!] Backup is $size_bytes bytes, partition is $want_bytes bytes.";
    ui_print "[!] The copy may be incomplete; keep it, but do not rely on it.";
  else
    ui_print "[+] Boot backup saved ($size_bytes bytes):";
    ui_print "    $dst/boot.img";
    ui_print "[+] Restore with: dd if=$dst/boot.img of=$BLOCK";
  fi
}

# ── Pre-flight ─────────────────────────────────────────────────────────
[ -b "$BLOCK" ] || abort " " "boot partition not found at $BLOCK. Aborting...";

[ -f Image.gz ] || abort " " "Image.gz is missing from this zip. Aborting...";

# gzip magic (1f 8b): refuse to flash something that is not a compressed
# kernel, because flash_boot() would write it and the device would not boot.
if [ "$(od -An -tx1 -N2 Image.gz 2>/dev/null | tr -d ' \n')" != "1f8b" ]; then
  abort " " "Image.gz is not a gzip stream. Aborting...";
fi

backup_boot;

ui_print " ";
ui_print "[+] Splitting the current boot image . . .";
split_boot;

# Where the device tree lives decides whether image-only flashing is safe:
#  * separate "dtb" section (the usual atoll layout): magiskboot keeps it and
#    repacks it unchanged, so we simply leave it alone;
#  * device tree appended to the kernel itself (legacy Image.gz-dtb): carry
#    that same blob behind our Image.gz so it is still there after the swap;
#  * neither: replacing the kernel would drop the device tree entirely and
#    the result would not boot -- refuse instead of shipping a brick.
if [ -s "$SPLITIMG/dtb" ]; then
  ui_print "[+] Keeping the existing DTB ($(wc -c < "$SPLITIMG/dtb") bytes).";
elif [ -s "$SPLITIMG/kernel_dtb" ]; then
  ui_print "[+] DTB is appended to the kernel; re-attaching the existing one.";
  cat Image.gz "$SPLITIMG/kernel_dtb" > Image.gz-dtb;
  [ -s Image.gz-dtb ] || abort " " "Failed to re-attach the device tree. Aborting...";
  rm -f Image.gz "$SPLITIMG/kernel_dtb";
else
  abort " " "This boot image carries no device tree. Aborting..." \
        " " "This zip replaces the kernel only and cannot supply a DTB." \
        " " "Nothing was written; the installed boot image is untouched.";
fi

# Advisory only: KernelSU-Next is built into this kernel, and a Magisk-patched
# ramdisk is not a supported combination.  AK3 would otherwise keep that patch
# silently, so say it out loud.
if ! ( cd "$SPLITIMG" && magiskboot cpio ramdisk.cpio test >/dev/null 2>&1 ); then
  ui_print " ";
  ui_print "[!] Magisk-patched ramdisk detected.";
  ui_print "[!] This kernel ships KernelSU-Next; running both is unsupported.";
fi

ui_print " ";
ui_print "[+] Repacking the boot image with the new kernel . . .";
flash_boot;

ui_print " ";
ui_print "[+] Done.";
ui_print "[+] Kernel replaced; DTB and dtbo left untouched.";
ui_print "[+] Reboot to apply.";
