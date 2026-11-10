#!/system/bin/sh
MODDIR=${0%/*}
. $MODDIR/lib.sh
if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then exit 0; fi
echo $$ > "$PIDF"
log "watcher start pid $$"
while true; do
  if [ ! -d "$CACHE" ]; then sleep 30; continue; fi
  scan_all
  # w = write closed, y = moved in (Glide writes key.0.tmp then renames)
  $BB inotifyd - "$CACHE:wy" | while read -r ev dir name; do
    case "$name" in *.0) ;; *) continue ;; esac
    k=${name%.0}
    if [ -d $CARDS/$k ]; then apply_card $k; else apply_dups; fi
  done
  log "inotifyd ended, retrying"
  sleep 5
done
