#!/system/bin/sh
# backend for the WebUI
MODDIR=${0%/*}
. $MODDIR/lib.sh
cmd=$1; k=$2
# commands that take a cache key: only accept a hex sha256
case "$cmd" in
  b64orig|b64custom|setimage|enable|restore|forget|label)
    case "$k" in ''|*[!0-9a-f]*) echo "bad key" >&2; exit 1 ;; esac ;;
esac
d=$CARDS/$k
case "$cmd" in
status)
  r=false; [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null && r=true
  echo "{\"watcher\":$r,\"root\":$([ "$(id -u)" = 0 ] && echo true || echo false)}" ;;
reapply)    # one-shot: re-apply every enabled card (used by the app, where no watcher runs)
  scan_all; echo ok ;;
list)
  KN=$(known_keys)
  DUPS=$(for x in $CARDS/*; do [ -f $x/dups ] && sed "s|\$| ${x##*/}|" $x/dups; done)
  { ls $CACHE 2>/dev/null | grep '\.0$' | sed 's/\.0$//'; ls $CARDS 2>/dev/null; } | sort -u | {
    echo '['; first=1
    while read -r k; do
      f=$CACHE/$k.0; d=$CARDS/$k; sz=0; mt=0; c=false
      [ -f "$f" ] && { sz=$(stat -c %s "$f"); mt=$(stat -c %Y "$f"); c=true; }
      [ "$sz" -gt 1500000 ] && [ ! -d $d ] && continue
      src=$(echo "$KN" | grep "^$k " | head -1 | cut -d' ' -f2)
      dup=$(echo "$DUPS" | grep "^$k " | head -1 | cut -d' ' -f2)
      en=false; [ -f $d/enabled ] && en=true
      cu=false; [ -f $d/custom.png ] && cu=true
      lb=$(cat $d/label 2>/dev/null)
      [ $first = 1 ] && first=0 || printf ','
      printf '{"key":"%s","size":%s,"mtime":%s,"cached":%s,"src":"%s","dupOf":"%s","enabled":%s,"custom":%s,"label":"%s"}\n' \
        "$k" "$sz" "$mt" "$c" "$src" "$dup" "$en" "$cu" "$lb"
    done
    echo ']'
  } ;;
b64orig)
  if [ -f $d/orig.0 ]; then $BB base64 -w 0 $d/orig.0; else $BB base64 -w 0 $CACHE/$k.0; fi ;;
b64custom)
  $BB base64 -w 0 $d/custom.png ;;
upload_reset)
  rm -f $ST/upload.b64 ;;
setimage)   # image was streamed into $ST/upload.b64
  mkdir -p $d
  [ -f $d/enabled ] && restore_card $k
  $BB base64 -d $ST/upload.b64 > $d/custom.png && rm -f $ST/upload.b64
  h $d/custom.png > $d/custom.sha
  touch $d/enabled
  apply_card $k; apply_dups
  echo ok ;;
enable)
  [ -f $d/custom.png ] || { echo "no image"; exit 1; }
  touch $d/enabled; apply_card $k; apply_dups; echo ok ;;
restore)
  restore_card $k; echo ok ;;
forget)
  restore_card $k; rm -rf $d; echo ok ;;
label)
  mkdir -p $d; printf '%s' "$3" | tr -d '"\\\n' > $d/label; echo ok ;;
loadpath)
  p=$2; case "$p" in /sdcard/*|/storage/*) ;; *) echo "bad path"; exit 1 ;; esac
  $BB base64 -w 0 "$p" ;;
restart)
  am force-stop $PKG; echo ok ;;
log)
  tail -n 40 $LOG ;;
esac
