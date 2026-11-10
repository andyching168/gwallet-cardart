# shared helpers for wallet_cardart
PKG=com.google.android.apps.walletnfcrel
DATA=/data/data/$PKG
CACHE=$DATA/cache/image_manager_disk_cache
PAYDB=/data/data/com.google.android.gms/databases/pay
ST=/data/adb/wallet_cardart
CARDS=$ST/cards
LOG=$ST/log.txt
PIDF=$ST/watcher.pid
BB=/data/adb/ksu/bin/busybox
[ -x $BB ] || BB=/data/adb/magisk/busybox
# no busybox (e.g. temporary root): use the system toybox applets directly
[ -x $BB ] || { command -v busybox >/dev/null 2>&1 && BB=busybox || BB=; }
mkdir -p $CARDS

log() {
  echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG"
  [ "$($BB wc -c < "$LOG")" -gt 65536 ] && $BB tail -n 200 "$LOG" > "$LOG.t" && mv "$LOG.t" "$LOG"
}
h() { $BB sha256sum "$1" 2>/dev/null | $BB cut -c1-64; }
shs() { printf '%s' "$1" | $BB sha256sum | $BB cut -c1-64; }

# "<cachekey> <source>" for every card-art URL we can find (Glide key = sha256(url))
known_keys() {
  for f in $DATA/files/common/*/*/*.pb; do
    [ -f "$f" ] || continue
    src=${f%/*}; src=${src##*/}
    $BB grep -aoE 'https://lh[0-9]\.googleusercontent\.com/wca/[A-Za-z0-9_-]+' "$f" | $BB sort -u | while read -r u; do
      echo "$(shs "$u") $src"
    done
  done
  [ -f $PAYDB ] && $BB grep -aoE 'https://lh[0-9]\.googleusercontent\.com/[A-Za-z0-9_-]{40,}' $PAYDB | $BB sort -u | while read -r u; do
    echo "$(shs "$u") pay"
  done
}

# put custom art into the cache for card $1 (in place: keeps owner/mode/SELinux label)
apply_card() {
  k=$1; d=$CARDS/$k; f=$CACHE/$k.0
  [ -f $d/enabled ] && [ -f $d/custom.png ] && [ -f "$f" ] || return 0
  cs=$(cat $d/custom.sha); fh=$(h "$f")
  [ "$fh" = "$cs" ] && return 0
  cp "$f" $d/orig.0; echo "$fh" > $d/orig.sha
  cat $d/custom.png > "$f" && log "apply $k (orig $fh)"
}

# other cache entries holding the same original image (e.g. a second URL variant)
apply_dups() {
  for f in "$CACHE"/*.0; do
    [ -f "$f" ] || continue
    n=${f##*/}; n=${n%.0}
    [ -d $CARDS/$n ] && continue
    fh=$(h "$f")
    for d in $CARDS/*; do
      [ -f $d/enabled ] && [ -f $d/orig.sha ] && [ "$(cat $d/orig.sha)" = "$fh" ] || continue
      cat $d/custom.png > "$f"
      $BB grep -qx "$n" $d/dups 2>/dev/null || echo "$n" >> $d/dups
      log "apply dup $n -> ${d##*/}"
      break
    done
  done
}

restore_card() {
  k=$1; d=$CARDS/$k
  rm -f $d/enabled
  [ -f $d/orig.0 ] || return 0
  cs=$(cat $d/custom.sha 2>/dev/null)
  for n in $k $(cat $d/dups 2>/dev/null); do
    f=$CACHE/$n.0
    [ -f "$f" ] && [ "$(h "$f")" = "$cs" ] && cat $d/orig.0 > "$f" && log "restore $n"
  done
  rm -f $d/dups
}

scan_all() {
  for d in $CARDS/*; do [ -d $d ] && apply_card ${d##*/}; done
  apply_dups
}
