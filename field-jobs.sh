#!/usr/bin/env bash
# field-jobs.sh — run the long field jobs in detached tmux sessions so they keep
# running after you disconnect SSH, and you can re-attach to see live output.
#
# RUN THIS ON THE SLAVE (the field Mac mini with the B200 + RTK rover attached),
# not on your laptop. SSH in, run `./field-jobs.sh start`, then disconnect; the
# jobs keep running. Reconnect later and `./field-jobs.sh attach rx` (or rtk) to
# watch, or `./field-jobs.sh logs rx` to tail the log. Detach from a tmux view
# with Ctrl-b then d (leaves it running).
#
# Jobs:
#   rtk  — RTK_dev_for_cm-loc RELPOSNED monitor (web dashboard, headless)
#   rx   — USRP_study_yishen/01-rx-to-ssd-b200-agc/run.sh (continuous RX → SSD, AGC)
#
# Usage:
#   ./field-jobs.sh start [rtk|rx]     # start both, or just one
#   ./field-jobs.sh attach <rtk|rx>    # attach to live output (Ctrl-b d to detach)
#   ./field-jobs.sh logs   <rtk|rx>    # tail -f the log file
#   ./field-jobs.sh status             # what's running
#   ./field-jobs.sh stop  [rtk|rx]     # stop both, or one
# Override autodetect:  REPO_BASE=/path  RTK_PORT=/dev/cu.usbmodemXXXX  RX_WEBPORT=8000
set -u

CMD="${1:-help}"; TARGET="${2:-}"
LOGDIR="$HOME/field-logs"; mkdir -p "$LOGDIR"

say()  { printf '\n\033[1;36m[field] %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }

# ── conda + tmux (resolved lazily; only some commands need them) ──────────────
CONDA_SH=""
for d in "$HOME/miniconda3" "$HOME/miniforge3" "$HOME/anaconda3"; do
  [ -f "$d/etc/profile.d/conda.sh" ] && CONDA_SH="$d/etc/profile.d/conda.sh" && break
done
TMUX_BIN="$(command -v tmux || true)"
[ -z "$TMUX_BIN" ] && [ -x "$HOME/miniconda3/envs/usrp/bin/tmux" ] && TMUX_BIN="$HOME/miniconda3/envs/usrp/bin/tmux"
need_tmux() { [ -n "$TMUX_BIN" ] || { warn "tmux not found. Add it: conda install -n usrp tmux  (or brew install tmux)"; exit 1; }; }
need_conda() { [ -n "$CONDA_SH" ] || { warn "conda not found — run 10-usrp-conda-env.sh first"; exit 1; }; }

# ── locate the repos (default: parent of this kit, then ~/Projects, then ~) ───
find_dir() {  # $1 = repo name
  for b in "${REPO_BASE:-}" "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" "$HOME/Projects" "$HOME"; do
    [ -n "$b" ] && [ -d "$b/$1" ] && { echo "$b/$1"; return 0; }
  done
  return 1
}
RTK_DIR="$(find_dir RTK_dev_for_cm-loc || true)"
RX_DIR="$(find_dir USRP_study_yishen || true)"; [ -n "$RX_DIR" ] && RX_DIR="$RX_DIR/01-rx-to-ssd-b200-agc"

# inner command runner: source conda, activate usrp, cd, run, tee to a log
wrap() {  # $1=dir  $2=command  $3=logfile
  printf 'source %q; { conda activate usrp; } 2>/dev/null; cd %q || exit 1; echo "[field] $(date) starting: %s"; %s 2>&1 | tee -a %q' \
    "$CONDA_SH" "$1" "$2" "$2" "$3"
}

start_one() {
  case "$1" in
    rtk)
      [ -z "$RTK_DIR" ] && { warn "RTK_dev_for_cm-loc not found (set REPO_BASE)"; return 1; }
      "$TMUX_BIN" has-session -t rtk 2>/dev/null && { ok "rtk already running (attach: ./field-jobs.sh attach rtk)"; return 0; }
      local port="${RTK_PORT:-$(ls /dev/cu.usbmodem* 2>/dev/null | head -1)}"
      [ -z "$port" ] && warn "no /dev/cu.usbmodem* found — plug in the rover, or set RTK_PORT"
      local web="${RX_WEBPORT:-8000}"
      local cmd="python relposned_monitor.py --mode web --host 0.0.0.0 --web-port $web --port ${port:-/dev/cu.usbmodem212301}"
      "$TMUX_BIN" new-session -d -s rtk "$(wrap "$RTK_DIR" "$cmd" "$LOGDIR/rtk.log")"
      ok "rtk started → web dashboard at http://<this-mac-ip>:$web  (log: $LOGDIR/rtk.log)" ;;
    rx)
      [ -z "$RX_DIR" ] && { warn "USRP 01-rx-to-ssd-b200-agc not found (set REPO_BASE)"; return 1; }
      "$TMUX_BIN" has-session -t rx 2>/dev/null && { ok "rx already running (attach: ./field-jobs.sh attach rx)"; return 0; }
      # run.sh respects an already-active conda env (won't switch to base).
      "$TMUX_BIN" new-session -d -s rx "$(wrap "$RX_DIR" "./run.sh" "$LOGDIR/rx.log")"
      ok "rx started → 01-rx-to-ssd-b200-agc/run.sh  (log: $LOGDIR/rx.log)" ;;
    *) warn "unknown job '$1' (use rtk or rx)"; return 1 ;;
  esac
}

case "$CMD" in
  start)
    need_tmux; need_conda
    say "Starting field jobs in tmux (survive SSH disconnect)"
    if [ -n "$TARGET" ]; then start_one "$TARGET"; else start_one rtk; start_one rx; fi
    say "Reconnect later, then:  ./field-jobs.sh attach rx   (or rtk) ·  ./field-jobs.sh logs rx" ;;
  attach)
    need_tmux; [ -z "$TARGET" ] && { warn "which? ./field-jobs.sh attach rx|rtk"; exit 1; }
    exec "$TMUX_BIN" attach -t "$TARGET" ;;
  logs)
    [ -z "$TARGET" ] && { warn "which? ./field-jobs.sh logs rx|rtk"; exit 1; }
    exec tail -f "$LOGDIR/$TARGET.log" ;;
  status)
    need_tmux; say "tmux sessions"; "$TMUX_BIN" ls 2>/dev/null || echo "  (none)"
    say "logs in $LOGDIR"; ls -la "$LOGDIR" 2>/dev/null ;;
  stop)
    need_tmux
    if [ -n "$TARGET" ]; then "$TMUX_BIN" kill-session -t "$TARGET" 2>/dev/null && ok "stopped $TARGET" || warn "no session $TARGET";
    else for s in rtk rx; do "$TMUX_BIN" kill-session -t "$s" 2>/dev/null && ok "stopped $s"; done; fi ;;
  *)
    sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
esac
