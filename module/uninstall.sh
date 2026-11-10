#!/system/bin/sh
MODDIR=${0%/*}
. $MODDIR/lib.sh
for d in $CARDS/*; do [ -d $d ] && restore_card ${d##*/}; done
rm -rf $ST
