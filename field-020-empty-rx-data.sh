#!/usr/bin/env bash
# field-020-empty-rx-data.sh — DELETE all RX capture data on this Mac (mini), after
# THREE typed confirmations. Interactive only; nothing is removed until all
# three pass, and any wrong answer aborts immediately.
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

# ── show exactly what would be deleted ───────────────────────────────────────
say "RX data dir: $DATA_DIR"
N_ITEMS="$(ls -A "$DATA_DIR" 2>/dev/null | wc -l | tr -d ' ')"
[ "$N_ITEMS" = "0" ] && { ok "already empty — nothing to delete."; exit 0; }
TOTAL="$(du -sh "$DATA_DIR" 2>/dev/null | awk '{print $1}')"
echo
du -sh "$DATA_DIR"/* 2>/dev/null | sort -rh | head -25 | sed 's/^/    /'
[ "$N_ITEMS" -gt 25 ] && echo "    … ($((N_ITEMS-25)) more)"
echo
warn "This will PERMANENTLY delete the $N_ITEMS item(s) above — $TOTAL total."
warn "The dir itself is kept; only its contents go."

# ── confirmation 1/3: yes ────────────────────────────────────────────────────
printf '\n  [1/3] Delete ALL RX data listed above? Type  yes  : '
read -r a1; [ "$a1" = "yes" ] || abort "confirmation 1 not 'yes'."

# ── confirmation 2/3: type the item count (proves the summary was read) ──────
printf '  [2/3] How many items will be deleted? Type  %s  : ' "$N_ITEMS"
read -r a2; [ "$a2" = "$N_ITEMS" ] || abort "confirmation 2 mismatch."

# ── confirmation 3/3: DELETE ─────────────────────────────────────────────────
printf '  [3/3] Last chance — type  DELETE  (uppercase) : '
read -r a3; [ "$a3" = "DELETE" ] || abort "confirmation 3 not 'DELETE'."

# ── do it ────────────────────────────────────────────────────────────────────
say "Deleting…"
BEFORE="$(df -h "$DATA_DIR" | awk 'NR==2{print $4}')"
# contents only; find -mindepth 1 avoids the dir itself and hidden-file globs
find "$DATA_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
AFTER="$(df -h "$DATA_DIR" | awk 'NR==2{print $4}')"
ok "emptied $DATA_DIR  (free space: $BEFORE → $AFTER)"
say "Done."
