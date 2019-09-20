#!/sbin/sh
# Tissot Manager install script by CosmicDan, edited by Giovix92
# Parts based on AnyKernel2 Backend by osm0sis
#

# This script is called by Aroma installer via update-binary-installer

######
# INTERNAL FUNCTIONS

OUTFD=/proc/self/fd/$2;
ZIP="$3";
DIR=`dirname "$ZIP"`;

ui_print() {
    until [ ! "$1" ]; do
        echo -e "ui_print $1\nui_print" > $OUTFD;
        shift;
    done;
}

show_progress() { echo "progress $1 $2" > $OUTFD; }
set_progress() { echo "set_progress $1" > $OUTFD; }

getprop() { test -e /sbin/getprop && /sbin/getprop $1 || file_getprop /default.prop $1; }
abort() { ui_print "$*"; umount /system; umount /data; exit 1; }

######

source /tissot_manager/constants.sh
source /tissot_manager/tools.sh

# SELinux patch
if [ -f "/tmp/doselinux" ]; then
	rm /tmp/doselinux
	boot_slot=`getBootSlotLetter`
	ui_print "[#] Dumping boot.img from slot $boot_slot ..."
	dumpAndSplitBoot $boot_slot

	# we'll cat the actual dumped commandline here as an additional verification
	cmdline=`cat /tmp/boot_split/boot.img-cmdline`
	if echo $cmdline | grep -Fqe "androidboot.selinux=permissive"; then
    ui_print "[i] SELinux status: permissive!"
    ui_print "[i] Patching to enforcing..."
		sed -i 's|androidboot.selinux=permissive|androidboot.selinux=enforcing|' "/tmp/boot_split/boot.img-cmdline"
	elif echo $cmdline | grep -Fqe "androidboot.selinux=enforcing"; then
    ui_print "[i] SELinux status: enforcing!"
    ui_print "[i] Patching to permissive..."
		sed -i 's|androidboot.selinux=enforcing|androidboot.selinux=permissive|' "/tmp/boot_split/boot.img-cmdline"
	else
		# missing selinux flag, just add permissive before the buildvariant
    ui_print "[i] SELinux status: unknown!"
    ui_print "[i] Patching to permissive..."
		sed -i 's| buildvariant=| androidboot.selinux=permissive buildvariant=|' "/tmp/boot_split/boot.img-cmdline"
	fi
	ui_print "[i] Patched kernel cmdline"
	ui_print "[#] Repacking patched boot.img..."
	bootimg cvf "/tmp/boot-new.img" "/tmp/boot_split"
	if [ -f "/tmp/boot-new.img" ]; then
		ui_print "[#] Flashing patched boot.img..."
		dd if=/tmp/boot-new.img of=/dev/block/bootdevice/by-name/boot_$boot_slot
		rm /tmp/boot-new.img
	else
		ui_print "[!] Error occured while repacking boot.img, cannot patch. See log for details."
		rm -rf /tmp/boot_split
		exit 0
	fi
	ui_print "[i] Done!"
	exit 0
fi

# Enable Treble, data
if [ -f "/tmp/dotrebledata" ]; then
  rm /tmp/dotrebledata
  ui_print "[i] Starting Treble repartition by shrinking data..."
  userdata_partline=`sgdisk --print /dev/block/mmcblk0 | grep -i userdata`
  userdata_partnum_current=$(echo "$userdata_partline" | awk '{ print $1 }')
  userdata_partstart_current=$(echo "$userdata_partline" | awk '{ print $2 }')
  userdata_partend_current=$(echo "$userdata_partline" | awk '{ print $3 }')
  ui_print "[#] Shrinking userdata..."
  sgdisk /dev/block/mmcblk0 --delete $userdata_partnum_current
  sgdisk /dev/block/mmcblk0 --new=$userdata_partnum_current:$userdata_treble_partstart:$userdata_partend_current
  sgdisk /dev/block/mmcblk0 --change-name=$userdata_partnum_current:userdata
  ui_print "[#] Creating vendor_a..."
  sgdisk /dev/block/mmcblk0 --new=$vendor_a_partnum:$vendor_a_partstart_userdata:$vendor_a_partend_userdata
  sgdisk /dev/block/mmcblk0 --change-name=$vendor_a_partnum:vendor_a
  ui_print "[#] Creating vendor_b..."
  sgdisk /dev/block/mmcblk0 --new=$vendor_b_partnum:$vendor_b_partstart_userdata:$vendor_b_partend_userdata
  sgdisk /dev/block/mmcblk0 --change-name=$vendor_b_partnum:vendor_b
  sleep 2
  blockdev --rereadpt /dev/block/mmcblk0
  sleep 1
  userdata_new_partlength_sectors=$((userdata_partend_current-userdata_treble_partstart))
  ui_print "[i] Userdata sectors: $userdata_new_partlength_sectors"
  userdata_new_partlength_bytes=$((userdata_new_partlength_sectors*512))
  ui_print "[i] Userdata bytes: $userdata_new_partlength_bytes"
  userdata_new_ext4size=$((userdata_new_partlength_bytes-16384))
  ui_print "[i] Userdata new size noef: $userdata_new_ext4size"
  ui_print "[#] Formatting userdata..."
  make_ext4fs -a /data -l $userdata_new_ext4size /dev/block/mmcblk0p$userdata_partnum_current
  ui_print "[#] Formatting vendor_a and vendor_b..."
  sleep 2
  make_ext4fs /dev/block/mmcblk0p$vendor_a_partnum
  make_ext4fs /dev/block/mmcblk0p$vendor_b_partnum
  ui_print "[i] All done!"
  ui_print "[i] You are now ready to install a any ROM (non-Treble or Treble) and/or Vendor pack."
fi

# Remove Treble, data
if [ -f "/tmp/remtrebledata" ]; then
  rm /tmp/remtrebledata
  ui_print "[i] Starting repartition back to stock..."
  ui_print "[#] Deleting vendor_a..."
  sgdisk /dev/block/mmcblk0 --delete $vendor_a_partnum
  ui_print "[#] Deleting vendor_b..."
  sgdisk /dev/block/mmcblk0 --delete $vendor_b_partnum
  sleep 1
  blockdev --rereadpt /dev/block/mmcblk0
  sleep 0.5
  userdata_partline=`sgdisk --print /dev/block/mmcblk0 | grep -i userdata`
  userdata_partnum_current=$(echo "$userdata_partline" | awk '{ print $1 }')
  userdata_partstart_current=$(echo "$userdata_partline" | awk '{ print $2 }')
  userdata_partend_current=$(echo "$userdata_partline" | awk '{ print $3 }')
  ui_print "[#] Growing userdata..."
  sgdisk /dev/block/mmcblk0 --delete $userdata_partnum
  sgdisk /dev/block/mmcblk0 --new=$userdata_partnum:$userdata_stock_partstart:$userdata_partend_current
  sgdisk /dev/block/mmcblk0 --change-name=$userdata_partnum:userdata
  ui_print "[#] Formatting userdata..."
  sleep 2
  blockdev --rereadpt /dev/block/mmcblk0
  sleep 1
  userdata_new_partlength_sectors=`echo $((userdata_partend_current-userdata_stock_partstart))`
  userdata_new_partlength_bytes=`echo $((userdata_new_partlength_sectors*512))`
  userdata_new_ext4size=`echo $((userdata_new_partlength_bytes-16384))`
  make_ext4fs -a /data -l $userdata_new_ext4size /dev/block/mmcblk0p$userdata_partnum_current
  ui_print "[i] All done!"
  ui_print "[i] You are now ready to install a non-Treble ROM or restore from a ROM backup."
fi

# Backup TWRP
if [ -f "/tmp/backuptwrp" ]; then
  backupTwrp
fi

# Restore TWRP
if [ -f "/tmp/restoretwrp" ]; then
  restoreTwrp
fi
