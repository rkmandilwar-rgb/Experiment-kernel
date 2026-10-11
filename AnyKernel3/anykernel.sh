# AnyKernel3 Ramdisk Mod Script
# osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=Stormbreaker by swiitchOFF @ github
kernel.compiler=Neutron Clang (LLVM)
kernel.made=CI/CD
kernel.version=
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
BLOCK=/dev/block/bootdevice/by-name/boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# boot install
dump_boot;
write_boot; # this also flashes vendor_dlkm, system_dlkm and dtbo if present
## end boot install


## Stormbreaker performance tuning (Magisk service.d)
if [ -d /data/adb/service.d ]; then
  cp ramdisk/stormbreaker-tuning.sh /data/adb/service.d/stormbreaker-tuning.sh
  chmod 0755 /data/adb/service.d/stormbreaker-tuning.sh
  ui_print "- Stormbreaker tuning installed (Magisk service.d)"
elif [ -d /system/etc/init.d ]; then
  cp ramdisk/stormbreaker-tuning.sh /system/etc/init.d/stormbreaker-tuning.sh
  chmod 0755 /system/etc/init.d/stormbreaker-tuning.sh
  ui_print "- Stormbreaker tuning installed (init.d)"
else
  ui_print "- No service.d/init.d found, skipping tuning script"
fi