#!/system/bin/sh
MODDIR=${0%/*}
until [ "$(getprop sys.boot_completed)" = 1 ] && [ -d /data/data ]; do sleep 5; done
sleep 10
nohup sh "$MODDIR/watcher.sh" >/dev/null 2>&1 &
