# AnyKernel3 Ramdisk Mod Script
# osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=Stormbreaker by swiitchOFF @ github
kernel.compiler=LLVM 22 (Clang/LLD)
kernel.made=CI/CD
kernel.version=4.14.357-openela
message.word=
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
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

# Back up the current boot and DTBO first when /data is available. This ZIP
# only flashes boot; the DTBO backup is kept as an extra recovery option.
backup_partition() {
  backup_src=$1;
  backup_dst=$2;
  backup_name=$3;

  if [ ! -b "$backup_src" ]; then
    ui_print "[!] $backup_name partition not found; skipping backup. ";
    return 1;
  fi;

  if dd if="$backup_src" of="$backup_dst" bs=4096; then
    ui_print "[+] $backup_name backup saved: $backup_dst";
  else
    rm -f "$backup_dst";
    ui_print "[!] $backup_name backup failed; proceeding anyway. ";
    return 1;
  fi;
}

backup_original_partitions() {
  if ! mountpoint -q /data; then
    ui_print "[!] /data is not mounted; skipping optional boot backups. ";
    return;
  fi;

  backup_stamp=$(date +%Y%m%d-%H%M%S 2>/dev/null);
  [ -n "$backup_stamp" ] || backup_stamp=latest;
  backup_dir="/sdcard/Stormbreaker-backup-$backup_stamp";

  if ! mkdir -p "$backup_dir"; then
    ui_print "[!] Cannot create backup folder on /sdcard; proceeding anyway. ";
    return;
  fi;

  ui_print " ";
  ui_print "[+] Backing up boot and existing DTBO . . .";
  backup_partition "$BLOCK" "$backup_dir/boot.img" "Boot";
  backup_partition /dev/block/bootdevice/by-name/dtbo "$backup_dir/dtbo.img" "DTBO";
}

backup_original_partitions;

## AnyKernel install
# Reuse the device's existing ramdisk/DTB and flash only the new kernel image.
# Do not call write_boot here: this AK3 core's write_boot also flashes DTBO.
split_boot;
flash_boot;
## end install
