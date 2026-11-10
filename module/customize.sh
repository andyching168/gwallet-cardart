SKIPUNZIP=0
set_perm_recursive $MODPATH 0 0 0755 0644
mkdir -p /data/adb/wallet_cardart/cards
ui_print "- State lives in /data/adb/wallet_cardart (kept across updates)"
ui_print "- Open this module's WebUI to manage card art"
