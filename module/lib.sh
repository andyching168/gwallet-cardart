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

# Create a cache entry Glide never wrote, e.g. when the card art URL fails to download
# (seen in the wild: a 403 from lh3.googleusercontent.com/wca/...). Glide checks its disk cache
# before the network, so a seeded entry is used as-is. Wallet must not be running: Glide only
# reads the journal on startup and rewrites it from memory later.
seed_card() {
  k=$1; d=$CARDS/$k; f=$CACHE/$k.0
  [ -d "$CACHE" ] && [ -f "$CACHE/journal" ] || return 0
  am force-stop $PKG
  cat $d/custom.png > "$f"
  chown "$(stat -c %u:%g "$CACHE")" "$f"; chmod 600 "$f"
  chcon "$(ls -dZ "$CACHE" | cut -d' ' -f1)" "$f" 2>/dev/null
  printf 'CLEAN %s %s\n' "$k" "$(stat -c %s "$f")" >> "$CACHE/journal"
  touch $d/seeded
  log "seed $k (no cached original)"
}

# put custom art into the cache for card $1 (in place: keeps owner/mode/SELinux label)
apply_card() {
  k=$1; d=$CARDS/$k; f=$CACHE/$k.0
  [ -f $d/enabled ] && [ -f $d/custom.png ] || return 0
  if [ ! -f "$f" ]; then
    # only seed art URLs Wallet still refers to (stale keys would just be evicted again)
    echo "$KEYS" | $BB grep -q "^$k " && seed_card $k
    return 0
  fi
  cs=$(cat $d/custom.sha); fh=$(h "$f")
  [ "$fh" = "$cs" ] && return 0
  cp "$f" $d/orig.0; echo "$fh" > $d/orig.sha
  rm -f $d/seeded   # Glide got the real image after all: it is now a normal backup/restore
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
  if [ -f $d/seeded ]; then   # we created this entry: drop it again
    am force-stop $PKG
    rm -f "$CACHE/$k.0"
    printf 'REMOVE %s\n' "$k" >> "$CACHE/journal"
    rm -f $d/seeded; log "unseed $k"
    return 0
  fi
  [ -f $d/orig.0 ] || return 0
  cs=$(cat $d/custom.sha 2>/dev/null)
  for n in $k $(cat $d/dups 2>/dev/null); do
    f=$CACHE/$n.0
    [ -f "$f" ] && [ "$(h "$f")" = "$cs" ] && cat $d/orig.0 > "$f" && log "restore $n"
  done
  rm -f $d/dups
}

scan_all() {
  KEYS=$(known_keys)
  for d in $CARDS/*; do [ -d $d ] && apply_card ${d##*/}; done
  apply_dups
}
