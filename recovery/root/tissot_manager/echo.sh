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

ui_print "[i] Test passed! Well done! :D"
