#!/system/bin/sh
MODDIR=${0%/*}
nohup sh "$MODDIR/watcher.sh" >/dev/null 2>&1 &
sleep 2
am force-stop com.google.android.apps.walletnfcrel
echo "Applied. Reopen Google Wallet. Open the WebUI to manage cards."
tail -n 5 /data/adb/wallet_cardart/log.txt 2>/dev/null
