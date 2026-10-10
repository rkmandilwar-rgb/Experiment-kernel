### AnyKernel3 Ramdisk Mod Script (Stormbreaker kernel, miatoll family)
## osm0sis @ xda-developers (template); configured for single-boot-partition (non A/B) devices

### AnyKernel setup
# global properties
properties() { '
kernel.string=Stormbreaker Kernel for miatoll (Curtana/Excalibur/Gram/Joyeuse)
do.devicecheck=1
do.modules=1
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=miatoll
device.name2=curtana
device.name3=excalibur
device.name4=gram
device.name5=joyeuse
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install
## boot files attributes
boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

# boot shell variables
# Single boot partition (no boot_a / boot_b): IS_SLOT_DEVICE must stay 0.
BLOCK=/dev/block/bootdevice/by-name/boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# Payload files packed in this zip (AnyKernel looks for them automatically):
#   Image.gz     : compressed kernel
#   dtb          : concatenated device tree blobs (appended to the kernel by ak3-core)
#   dtbo.img     : device tree overlay image -> flashed to the dtbo partition by write_boot
#   modules/     : kernel modules (NetHunter Wi-Fi/BT/USB drivers), installed by do.modules=1

# boot install
dump_boot; # use split_boot to skip ramdisk unpack, e.g. for devices with init_boot ramdisk

write_boot; # use flash_boot to skip ramdisk repack, e.g. for devices with init_boot ramdisk
## end boot install
