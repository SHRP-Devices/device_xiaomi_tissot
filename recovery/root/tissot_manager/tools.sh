#!/sbin/sh

# Various tools for Tissot TWRP by CosmicDan
# Parts from LazyFlasher boot image patcher script by jcadduono

source /tissot_manager/constants.sh

ui_print() {
	if [ "$OUT_FD" ]; then
		if [ "$1" ]; then
			echo "ui_print $1" > "$OUT_FD"
		else
			echo "ui_print  " > "$OUT_FD"
		fi
	else
		echo "$1"
	fi
}

# set to a fraction (where 1.0 = 100%)
set_progress() {
	echo "set_progress $1" > "$OUT_FD"
}

# find the recovery text output pipe (it's always the last one found)
for l in /proc/self/fd/*; do 
	# set the last pipe: target
	if readlink $l | grep -Fqe 'pipe:'; then
		OUT_FD=$l
	fi
done

file_getprop() { grep "^$2" "$1" | cut -d= -f2; }

getCurrentSlotLetter() {
	systemSymlink=`readlink /dev/block/bootdevice/by-name/system` 2>/dev/null
	echo -n $systemSymlink 2>/dev/null | tail -c 1 2>/dev/null
}

getBootSlotLetter() {
	getprop ro.boot.slot_suffix 2>/dev/null | sed 's|_||' 2>/dev/null
}

getOtherSlotLetter() {
	if [ `getBootSlotLetter` = "a" ]; then
		echo -n "b" 2>/dev/null
	else
		echo -n "a" 2>/dev/null
	fi
}

isTreble() {
	if [ -b "/dev/block/bootdevice/by-name/vendor_a" -a -b "/dev/block/bootdevice/by-name/vendor_b" ]; then
		# return 0 = true
		return 0 
	else
		# return 1 = false
		return 1
	fi
}

hasDualbootUserdata() {
	if [ -b "/dev/block/bootdevice/by-name/userdata_a" -a -b "/dev/block/bootdevice/by-name/userdata_b" ]; then
		# return 0 = true
		return 0 
	else
		# return 1 = false
		return 1
	fi
}

isHotBoot() {
	if cat /proc/cmdline | grep -Fqe " gpt "; then
		# " gpt " in kernel cmdline = real boot
		return 1
	else
		# no " gpt " = fastboot hotboot
		return 0
	fi
}

isModdedUpdateEngine() {
	if [ -f "/sbin/update_engine_sideload_cosmicmod" ]; then
		# remember: 0 = true with return codes
		return 0
	else
		return 1
	fi
}

isTrebleKernel() {
	if cat /sys/firmware/devicetree/base/firmware/android/fstab/vendor/fsmgr_flags | grep -Fqe "slotselect"; then
		# true/success
		return 0
	else
		# false/error
		return 1
	fi
}

# Checks if current slot is dualboot patched or not.
# returns:
# "dualboot" for dualboot patched
# "singleboot" for singleboot standard
# "na" for error (missing or incompatible fstab)
doDualbootCheck() {
	echo "na" > /tmp/dualboot_check
	umount -f /system > /dev/null 2>&1
	if isTreble; then
		umount -f /vendor > /dev/null 2>&1
	fi
	if [ "$1" = "" ]; then
		targetSlot=`getCurrentSlotLetter`
	else
		targetSlot="$1"
	fi
	
	mount "/dev/block/bootdevice/by-name/system_$targetSlot" /system > /dev/null 2>&1
	if isTreble; then
		mount "/dev/block/bootdevice/by-name/vendor_$targetSlot" /vendor > /dev/null 2>&1
	fi

	if [ -f "/system/system/vendor/etc/fstab.qcom" ]; then
		# We want to loop over all matching lines because there could be multiple userdata mounts (e.g. for ext4 and f2fs ROM's)
		cat "/system/system/vendor/etc/fstab.qcom" | grep "/dev/block/bootdevice/by-name/userdata" | while read -r LINE; do
			if echo $LINE | grep -Fqe ",slotselect"; then
				echo "dualboot" > /tmp/dualboot_check
			else
				echo "singleboot" > /tmp/dualboot_check
			fi
		done
	fi
	retval=`cat /tmp/dualboot_check`
	echo -n $retval
	rm /tmp/dualboot_check
	echo "result=$retval" > /tmp/result.prop
    echo "$result" > /tmp/dualbootstatus
	if [ "$2" != "noUnmount" ]; then
		umount -f /vendor > /dev/null 2>&1
		umount -f /system > /dev/null 2>&1
	fi
}

# Patches the current slot vendor and/or system for dualboot (or back)
# returns:
# "dualboot" for dualboot patch succeeded
# "singleboot" for singleboot patch succeeded
# "na" for error (missing or incompatible fstab)
doDualbootPatch() {
	echo "na" > /tmp/dualboot_patch
	if [ "$1" = "" ]; then
		targetSlot=`getCurrentSlotLetter`
	else
		targetSlot="$1"
	fi
	doDualbootCheck $targetSlot noUnmount
	dualbootCheck=`file_getprop /tmp/result.prop result`
	rm "/tmp/fstab.qcom.new" > /dev/null 2>&1
	if [ -f "/system/system/vendor/etc/fstab.qcom" -a "$dualbootCheck" != "na" ]; then
		# loop over the existing fstab and create a new one, modifying as necessary. Simplest way to replace a string in specific matching line
		{
			IFS=''
			cat "/system/system/vendor/etc/fstab.qcom" | while read LINE; do
				if echo $LINE | grep -Fqe "/dev/block/bootdevice/by-name/userdata"; then
					if [ "$dualbootCheck" = "dualboot" ]; then
						LINE=`echo $LINE | sed 's|,slotselect||'`
						echo "singleboot" > /tmp/dualboot_patch
					elif [ "$dualbootCheck" = "singleboot" ]; then
						LINE=`echo $LINE | sed 's|wait,|wait,slotselect,|'`
						echo "dualboot" > /tmp/dualboot_patch
					fi
				fi
				echo $LINE >> "/tmp/fstab.qcom.new"
			done
		}
		mv -f "/tmp/fstab.qcom.new" "/system/system/vendor/etc/fstab.qcom"
		chmod 0644 "/system/system/vendor/etc/fstab.qcom"
		chown root:root "/system/system/vendor/etc/fstab.qcom"
		restorecon -v "/system/system/vendor/etc/fstab.qcom"
	fi
	retval=`cat /tmp/dualboot_patch`
	echo -n $retval
	echo "result=$retval" > /tmp/result.prop
	rm /tmp/dualboot_patch > /dev/null 2>&1
	rm /tmp/fstab.qcom.new > /dev/null 2>&1
	if isTreble; then
		umount -f /vendor > /dev/null 2>&1
	fi
	umount -f /system > /dev/null 2>&1
}

# used by both update_engine_sideload and flash_image to patch vendor
dualBootInstallProcess() {
	ui_print "[#] Dual boot patch check..."
	deviceIsDualboot="false"
	if hasDualbootUserdata; then
		deviceIsDualboot="true"
	fi
	doDualbootCheck $1
	dualbootCheck=`file_getprop /tmp/result.prop result`
	rm /tmp/result.prop > /dev/null 2>&1
	if [ "$dualbootCheck" = "na" ]; then
		ui_print "    [!] ROM/Vendor is incompatible with dual boot, skipped."
	else
		if [ "$deviceIsDualboot" = "true" ]; then
			if [ "$dualbootCheck" = "singleboot" ]; then
				doDualbootPatch $1
				patchResult=`file_getprop /tmp/result.prop result`
				if [ "$patchResult" = "dualboot" ]; then
					ui_print "    [i] Dual boot patch succeeded!"
				else
					ui_print "    [i] Dual boot patch failed. Please save log and report this error and the vendor source."
				fi
			else
				ui_print "    [i] ROM/Vendor is already dual boot patched, skipped."
			fi
		elif [ "$deviceIsDualboot" = "false" ]; then
			if [ "$dualbootCheck" = "dualboot" ]; then
				doDualbootPatch $1
				patchResult=`file_getprop /tmp/result.prop result`
				if [ "$patchResult" = "singleboot" ]; then
					ui_print "    [i] ROM/Vendor was dual boot - is now patched for single boot."
				else
					ui_print "    [i] Single boot patch failed. Please save log and report this error and the vendor source."
				fi
			else
				ui_print "    [i] Device is single boot and so is ROM/Vendor - no patch necessary."
			fi
		fi
	fi
	rm /tmp/result.prop > /dev/null 2>&1
}

# internal
dumpAndSplitBoot() {
	dd if=/dev/block/bootdevice/by-name/boot_$1 of=/tmp/boot.img
	bootimg xvf /tmp/boot.img /tmp/boot_split
	rm /tmp/boot.img
}

backupTwrp() {
	if isHotBoot; then
		# Don't do anything if we're on a hotboot
		ui_print "[!] Skipping TWRP survival (unsupported in hotboot)"
		return
	fi
	boot_slot=`getBootSlotLetter`
	ui_print "[#] Backing up current RAMDisk from boot slot $boot_slot"
	ui_print "    (automatic TWRP survival)..."
	dumpAndSplitBoot $boot_slot
	mv /tmp/boot_split/boot.img-ramdisk /tmp/ramdisk-twrp-backup.img
	rm -rf /tmp/boot_split
	if [ ! -f "/tmp/ramdisk-twrp-backup.img" ]; then
		ui_print "    [!] Failed. Check Recovery log for details."
	fi
}

restoreTwrp() {
	if isHotBoot; then
		# Don't do anything if we're on a hotboot
		return
	fi
	targetSlot=$1
	if [ "$targetSlot" != "a" -a "$targetSlot" != "b" ]; then
		ui_print "[!] No target slot specified!"
		return
	fi
	if [ -f "/tmp/ramdisk-twrp-backup.img" ]; then
		ui_print "[#] Reinstalling TWRP to boot slot $targetSlot"
		ui_print "    (automatic TWRP survival)..."
		dumpAndSplitBoot $targetSlot
		if [ -f "/tmp/boot_split/boot.img-ramdisk" ]; then
			rm "/tmp/boot_split/boot.img-ramdisk"
			mv "/tmp/ramdisk-twrp-backup.img" "/tmp/boot_split/boot.img-ramdisk"
			bootimg cvf "/tmp/boot-new.img" "/tmp/boot_split"
			if [ -f "/tmp/boot-new.img" ]; then
				dd if=/tmp/boot-new.img of=/dev/block/bootdevice/by-name/boot_$targetSlot
				rm /tmp/boot-new.img
				touch /tmp/twrp_survival_success
				return
			fi
		fi
		ui_print "    [!] Failed. Check Recovery log for details."
	else
		ui_print "[!] Unable to perform TWRP survival: backup missing!"
	fi
}

shouldDoPayloadInstall() {
	bootSlot=`getBootSlotLetter`
	otherSlot=`getOtherSlotLetter`
	currentSlot=`getCurrentSlotLetter`
	umount -f /system
	for mountPoint in system_slot_boot system_slot_other; do
		if [ ! -d /$mountPoint ]; then
			mkdir /$mountPoint
		fi
		chmod 777 /$mountPoint
		umount -f /$mountPoint
	done
	mount -o ro /dev/block/bootdevice/by-name/system_$bootSlot /system_slot_boot
	mount -o ro /dev/block/bootdevice/by-name/system_$otherSlot /system_slot_other
	
	rm -f /tmp/aroma_prompt.prop
	for slotSelection in slot_boot slot_other; do
		if [ -f "/system_${slotSelection}/system/build.prop" ]; then
			# don't bother with any of this if it's an empty slot
			slotId=`cat "/system_${slotSelection}/system/build.prop" | grep -i "ro.build.display.id=" | sed 's|ro\.build\.display\.id=||'`
			if [ "$slotId" != "" ]; then
				echo "${slotSelection}_id=${slotId}" >> /tmp/aroma_prompt.prop
			else
				echo "${slotSelection}_id=Unknown [no ro.build.display.id prop found]" >> /tmp/aroma_prompt.prop
			fi
		fi
	done
	
	if [ "$bootSlot" = "a" ]; then
		echo "slot_boot_letter=A" >> /tmp/aroma_prompt.prop
		echo "slot_other_letter=B" >> /tmp/aroma_prompt.prop
	else
		echo "slot_boot_letter=B" >> /tmp/aroma_prompt.prop
		echo "slot_other_letter=A" >> /tmp/aroma_prompt.prop
	fi
	echo "slot_current=${currentSlot}" >> /tmp/aroma_prompt.prop
	
	# Do aroma prompt. It should touch /tmp/flash_confirm if the user agreed to install.
	# It can get the build ID and slot from /tmp/aroma_prompt.prop "id" and "slot" props respectively.
	pauseTwrp
	echo "task=flash_slot_prompt" >> /tmp/aroma_prompt.prop
	ui_print
	/tissot_manager/aroma 1 `basename $OUT_FD` /tissot_manager/tissot_manager.zip >/tmp/tissot_manager_prompt.log
	ui_print
	rm "/tmp/aroma_prompt.prop"
	umount -f /system_slot_boot
	umount -f /system_slot_other
	resumeTwrp
	
	if [ -f "/tmp/flash_skip_payload_verification" ]; then
		setprop tissotmanager.payload.ignoreverify 1
	else
		setprop tissotmanager.payload.ignoreverify 0
	fi
	rm -f "/tmp/flash_skip_payload_verification"
	
	if [ -f "/tmp/flash_confirm_other" ]; then
		setprop tissotmanager.payload.sameslot 0
		# return true
		rm "/tmp/flash_confirm_other"
		return 0
	elif [ -f "/tmp/flash_confirm_boot" ]; then
		setprop tissotmanager.payload.sameslot 1
		# return true
		rm "/tmp/flash_confirm_boot"
		return 0
	else
		ui_print "[!] Install aborted by user choice."
		# return false
		rm -f "/tmp/flash_skip_survival"
		return 1
	fi
}

userdataCalcUsageRemainingForSlotA() {
	userdata_capacity=`sgdisk --print /dev/block/mmcblk0 | grep -i userdata | awk '{ print $4 }'`
	userdata_start=`sgdisk --print /dev/block/mmcblk0 | grep -i userdata | awk '{ print $2 }'`
	userdata_end=`sgdisk --print /dev/block/mmcblk0 | grep -i userdata | awk '{ print $3 }'`
	userdata_length=`echo $((userdata_end-userdata_start))`
	if [ "$2" == "4gb" ]; then
		if [ "$3" == "as_sectors" ]; then
			userdata_a_shrunk=`dc $userdata_length 8388608 - p`
		else
			userdata_a_shrunk=`dc $userdata_capacity 4 - p`
		fi
	elif [ "$2" == "6gb" ]; then
		if [ "$3" == "as_sectors" ]; then
			userdata_a_shrunk=`dc $userdata_length 12582912 - p`
		else
			userdata_a_shrunk=`dc $userdata_capacity 6 - p`
		fi
	elif [ "$2" == "8gb" ]; then
		if [ "$3" == "as_sectors" ]; then
			userdata_a_shrunk=`dc $userdata_length 16777216 - p`
		else
			userdata_a_shrunk=`dc $userdata_capacity 8 - p`
		fi
	elif [ "$2" == "12gb" ]; then
		if [ "$3" == "as_sectors" ]; then
			userdata_a_shrunk=`dc $userdata_length 25165824 - p`
		else
			userdata_a_shrunk=`dc $userdata_capacity 12 - p`
		fi
	elif [ "$2" == "16gb" ]; then
		if [ "$3" == "as_sectors" ]; then
			userdata_a_shrunk=`dc $userdata_length 33554432 - p`
		else
			userdata_a_shrunk=`dc $userdata_capacity 16 - p`
		fi
	fi
	# subtract vendor_a and vendor_b
	if [ "$3" == "as_sectors" ]; then
		result=$((userdata_a_shrunk-2457600))
		echo -n $result
		echo -n "result=$result" > /tmp/result.prop
	else
		result=`dc $userdata_a_shrunk 1.2 - p`
		echo -n $result
		echo -n "result=$result" > /tmp/result.prop
	fi
}

pauseTwrp() {
	for pid in `pidof recovery`; do 
		kill -SIGSTOP $pid
	done;
}

resumeTwrp() {
	for pid in `pidof recovery`; do 
		kill -SIGCONT $pid
	done;
}

doSelinuxCheck() {
	result="unknown"
	cmdline=`cat /proc/cmdline`
	if echo $cmdline | grep -Fqe "androidboot.selinux=permissive"; then
		result="permissive"
	fi
	if echo $cmdline | grep -Fqe "androidboot.selinux=enforcing"; then
		result="enforcing"
	fi
	echo -n "$result"
	echo "result=$result" > /tmp/result.prop
    echo "$result" > /tmp/selinuxstatus
}

doEncryptionCheck() {
	echo "unknown" > /tmp/encryption_check
	umount -f /system > /dev/null 2>&1
	if isTreble; then
		umount -f /vendor > /dev/null 2>&1
	fi
	if [ "$1" = "" ]; then
		targetSlot=`getCurrentSlotLetter`
	else
		targetSlot="$1"
	fi
	
	mount "/dev/block/bootdevice/by-name/system_$targetSlot" /system > /dev/null 2>&1
	if isTreble; then
		mount "/dev/block/bootdevice/by-name/vendor_$targetSlot" /vendor > /dev/null 2>&1
	fi

	if [ -f "/system/system/vendor/etc/fstab.qcom" ]; then
		# We want to loop over all matching lines because there could be multiple userdata mounts (e.g. for ext4 and f2fs ROM's)
		cat "/system/system/vendor/etc/fstab.qcom" | grep "/dev/block/bootdevice/by-name/userdata" | while read -r LINE; do
			result=`cat /tmp/encryption_check`
			if echo $LINE | grep -Fqe ",forceencrypt=footer"; then
				if [ "$result" == "unknown" -o "$result" == "forced" ]; then
					echo "forced" > /tmp/encryption_check
				else
					# we got a different result than the last set result
					echo "invalid" > /tmp/encryption_check
				fi
			fi
			
			if echo $LINE | grep -Fqe ",encryptable=footer"; then
				if [ "$result" == "unknown" -o "$result" == "optional" ]; then
					echo "optional" > /tmp/encryption_check
				else
					# we got a different result than the last set result
					echo "invalid" > /tmp/encryption_check
				fi
			fi
		done
	fi
	result=`cat /tmp/encryption_check`
	echo -n "$result"
	if [ "$result" == "invalid" ]; then
		result="unknown"
	fi
	echo "result=$result" > /tmp/result.prop
	if [ "$2" != "noUnmount" ]; then
		umount -f /vendor > /dev/null 2>&1
		umount -f /system > /dev/null 2>&1
	fi
}

doEncryptionPatch() {
	echo "unknown" > /tmp/encryption_patch
	if [ "$1" = "" ]; then
		targetSlot=`getCurrentSlotLetter`
	else
		targetSlot="$1"
	fi
	encryptionCheck=`doEncryptionCheck $targetSlot noUnmount`
	rm "/tmp/fstab.qcom.new" > /dev/null 2>&1
	if [ -f "/system/system/vendor/etc/fstab.qcom" -a "$encryptionCheck" != "unknown" ]; then
		# loop over the existing fstab and create a new one, modifying as necessary. Simplest way to replace a string in specific matching line
		{
			IFS=''
			cat "/system/system/vendor/etc/fstab.qcom" | while read LINE; do
				if echo $LINE | grep -Fqe "/dev/block/bootdevice/by-name/userdata"; then
					if [ "$encryptionCheck" = "forced" ]; then
						LINE=`echo $LINE | sed 's|,forceencrypt=footer|,encryptable=footer|'`
						echo "optional" > /tmp/encryption_patch
					elif [ "$encryptionCheck" = "optional" ]; then
						LINE=`echo $LINE | sed 's|,encryptable=footer|,forceencrypt=footer|'`
						echo "forced" > /tmp/encryption_patch
					fi
				fi
				echo $LINE >> "/tmp/fstab.qcom.new"
			done
		}
		mv -f "/tmp/fstab.qcom.new" "/system/system/vendor/etc/fstab.qcom"
		chmod 0644 "/system/system/vendor/etc/fstab.qcom"
		chown root:root "/system/system/vendor/etc/fstab.qcom"
		restorecon -v "/system/system/vendor/etc/fstab.qcom"
	fi
	echo -n `cat /tmp/encryption_patch`
	rm /tmp/encryption_patch > /dev/null 2>&1
	rm /tmp/fstab.qcom.new > /dev/null 2>&1
	if isTreble; then
		umount -f /vendor > /dev/null 2>&1
	fi
	umount -f /system > /dev/null 2>&1
}

unmountAllAndRefreshPartitions() {
	stop sbinqseecomd
	sleep 1
	kill `pidof qseecomd`
	mount | grep /dev/block/mmcblk0p | while read -r line ; do
		thispart=`echo "$line" | awk '{ print $3 }'`
		umount -f $thispart
		sleep 0.5
	done
	mount | grep /dev/block/bootdevice/ | while read -r line ; do
		thispart=`echo "$line" | awk '{ print $3 }'`
		umount -f $thispart
		sleep 0.5
	done
	sleep 2
	blockdev --rereadpt /dev/block/mmcblk0
}

#################################
# Entrypoints for Tissot Manager

if [ "$1" == "userdata_calc" ]; then
	userdataCalcUsageRemainingForSlotA "$@"
	exit 0
elif [ "$1" == "doDualbootCheck" ]; then
	doDualbootCheck
	exit 0
elif [ "$1" == "doDualbootPatch" ]; then
	doDualbootPatch
	exit 0
elif [ "$1" == "hasDualbootUserdata" ]; then
	hasDualbootUserdata
	exit $?
elif [ "$1" == "isTrebleKernel" ]; then
	isTrebleKernel
	exit $?
elif [ "$1" == "isHotBoot" ]; then
	isHotBoot
	exit $?
elif [ "$1" == "doEncryptionCheck" ]; then
	doEncryptionCheck
	exit 0
elif [ "$1" == "doEncryptionPatch" ]; then
	doEncryptionPatch
	exit 0
elif [ "$1" == "doSelinuxCheck" ]; then
	doSelinuxCheck
	exit 0
elif [ "$1" == "getBootSlotLetter" ]; then
	echo -n `getBootSlotLetter`
fi
