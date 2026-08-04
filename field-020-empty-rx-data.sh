#!/usr/bin/env bash
# field-020-empty-rx-data.sh — DELETE RX capture records on this Mac (mini).
# Lists every record with its size, asks which to KEEP (Enter = the newest
# record only; numbers like 1,3 for your own pick; 0 = keep none), then one
# y/N confirmation. Interactive only; nothing is removed before the confirm.
#
# Target: the RX data dir, resolved as (first hit wins)
#   1. RX_DATA_DIR=/path            explicit override
#   2. OUT=… in 01-rx-to-ssd-b200-agc/run.conf (if set non-empty)
#   3. <USRP_study_yishen>/data     repo found via kit parent / /Volumes/USRP* /
#                                   ~/Projects / ~  (REPO_BASE=… to override)
# Deletes the CONTENTS of that dir (the <UTC>/ capture dirs etc.), never the
# dir itself, never anything outside it. Refuses while the rx job is running.
set -u

say()  { printf '\n\033[1;36m[empty-rx] %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }
abort(){ warn "$*"; warn "Nothing was deleted."; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# [c] like field-000-jobs.sh find_dir, plus /Volumes/USRP* (repos live on the
# capture SSD on some minis, e.g. /Volumes/USRP02/USRP_study_yishen)
find_repo() {
  for b in "${REPO_BASE:-}" "$(cd "$HERE/.." && pwd)" /Volumes/USRP* "$HOME/Projects" "$HOME"; do
    [ -n "$b" ] && [ -d "$b/USRP_study_yishen" ] && { echo "$b/USRP_study_yishen"; return 0; }
  done
  return 1
}

[ -t 0 ] || abort "interactive terminal required (three typed confirmations)."

# ── resolve the data dir ──────────────────────────────────────────────────────
DATA_DIR="${RX_DATA_DIR:-}"
if [ -z "$DATA_DIR" ]; then
  RX_CONF="$(find_repo || true)"; RX_CONF="${RX_CONF:+$RX_CONF/01-rx-to-ssd-b200-agc/run.conf}"
  if [ -n "$RX_CONF" ] && [ -f "$RX_CONF" ]; then
    DATA_DIR="$(sed -n 's/^OUT=\([^ #]*\).*/\1/p' "$RX_CONF" | head -1)"
  fi
fi
if [ -z "$DATA_DIR" ]; then
  REPO="$(find_repo)" || abort "USRP_study_yishen not found (set REPO_BASE or RX_DATA_DIR)."
  DATA_DIR="$REPO/data"
fi
[ -d "$DATA_DIR" ] || abort "data dir not found: $DATA_DIR"

# ── refuse while the rx capture job is running ───────────────────────────────
TMUX_BIN="$(command -v tmux || true)"
[ -z "$TMUX_BIN" ] && [ -x "$HOME/miniconda3/envs/usrp/bin/tmux" ] && TMUX_BIN="$HOME/miniconda3/envs/usrp/bin/tmux"
if [ -n "$TMUX_BIN" ] && "$TMUX_BIN" has-session -t rx 2>/dev/null; then
  abort "the rx capture job is RUNNING — stop it first:  $HERE/field-000-jobs.sh stop rx"
fi
# [c] also catch a capture running OUTSIDE tmux (seen on mac-02, 2026-08-03)
pgrep -f rx_to_ssd >/dev/null 2>&1 \
  && abort "an rx_to_ssd capture is RUNNING outside tmux (pgrep -fl rx_to_ssd) — stop it first"

# ── show exactly what would be deleted ───────────────────────────────────────
# ── [c] list the records (chronological), then pick what to KEEP + 1 confirm
# (Yi 2026-08-03: old 3-typed-answer flow too complicated)
say "RX data records in: $DATA_DIR"
N=0
for e in $(ls -A "$DATA_DIR" 2>/dev/null | sort); do N=$((N+1)); REC_NAMES="${REC_NAMES:-} $e"; done
[ "$N" = 0 ] && { ok "already empty — nothing to delete."; exit 0; }
i=1
for e in $REC_NAMES; do
  sz="$(du -sh "$DATA_DIR/$e" 2>/dev/null | cut -f1)"
  mark=""; [ "$i" = "$N" ] && mark="   ← newest"
  printf '  %2d) %-24s %6s%s\n' "$i" "$e" "$sz" "$mark"
  i=$((i+1))
done
echo "      total: $(du -sh "$DATA_DIR" 2>/dev/null | cut -f1) in $N record(s)"

printf '\n  Records to KEEP  [Enter = newest only · numbers e.g. 1,3 · 0 = keep none]: '
read -r keep_in
KEEP=" "
if [ -z "$keep_in" ]; then KEEP=" $N "
elif [ "$keep_in" != "0" ]; then
  for k in $(echo "$keep_in" | tr ',' ' '); do
    case "$k" in ''|*[!0-9]*) abort "'$k' is not a record number" ;; esac
    { [ "$k" -ge 1 ] && [ "$k" -le "$N" ]; } || abort "no record $k (valid: 1–$N)"
    KEEP="$KEEP$k "
  done
fi
DEL_NAMES=""; KEEP_NAMES=""; NDEL=0
i=1
for e in $REC_NAMES; do
  case "$KEEP" in
    *" $i "*) KEEP_NAMES="$KEEP_NAMES $e" ;;
    *)        DEL_NAMES="$DEL_NAMES $e"; NDEL=$((NDEL+1)) ;;
  esac
  i=$((i+1))
done
[ "$NDEL" = 0 ] && { ok "nothing selected for deletion."; exit 0; }
DELSZ="$(cd "$DATA_DIR" && du -sch $DEL_NAMES 2>/dev/null | tail -1 | cut -f1)"
warn "will PERMANENTLY delete $NDEL record(s), $DELSZ — keeping:${KEEP_NAMES:- nothing}"
# [c] 3 quick inputs total (selection + y + y), each a single key (Yi 2026-08-03)
printf '  confirm? [y/N]: '
read -r a; case "$a" in [yY]*) ;; *) abort "not confirmed." ;; esac
printf '  sure?    [y/N]: '
read -r a; case "$a" in [yY]*) ;; *) abort "not confirmed." ;; esac

say "Deleting…"
BEFORE="$(df -h "$DATA_DIR" | awk 'NR==2{print $4}')"
for e in $DEL_NAMES; do rm -rf "$DATA_DIR/$e"; done
AFTER="$(df -h "$DATA_DIR" | awk 'NR==2{print $4}')"
ok "deleted $NDEL record(s)  (free space: $BEFORE → $AFTER)"
say "Done."
