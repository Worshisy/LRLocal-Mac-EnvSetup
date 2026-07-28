#!/usr/bin/env bash
# field-000-jobs.sh — run the long field jobs in detached tmux sessions so they keep
# running after you disconnect SSH, and you can re-attach to see live output.
#
# RUN THIS ON THE SLAVE (the field Mac mini with the B200 + RTK rover attached),
# not on your laptop. SSH in, run `./field-000-jobs.sh start`, then disconnect; the
# jobs keep running. Reconnect later and `./field-000-jobs.sh attach rx` (or rtk) to
# watch, or `./field-000-jobs.sh logs rx` to tail the log. Detach from a tmux view
# with Ctrl-b then d (leaves it running).
#
# Jobs:
#   rtk  — RTK_dev_for_cm-loc RELPOSNED monitor (web dashboard, headless)
#   rx   — USRP_study_yishen/01-rx-to-ssd-b200-agc/run.sh (continuous RX → SSD, AGC)
#
# Usage:
#   ./field-000-jobs.sh start [rtk|rx]     # start both, or just one
#   ./field-000-jobs.sh attach <rtk|rx>    # attach to live output (Ctrl-b d to detach)
#   ./field-000-jobs.sh logs   <rtk|rx>    # tail -f the log file
#   ./field-000-jobs.sh status             # what's running
#   ./field-000-jobs.sh stop  [rtk|rx]     # stop both, or one
# Override autodetect:  REPO_BASE=/path  RTK_PORT=/dev/cu.usbmodemXXXX  RX_WEBPORT=8000
#                        RX_FREQ=2.44e9   (pre-answers the RX center-freq prompt)
#                        RX_START=18:30|now  RX_START_TZ=utc  (pre-answer the start-time prompt)
set -u

CMD="${1:-help}"; TARGET="${2:-}"
LOGDIR="$HOME/field-logs"; mkdir -p "$LOGDIR"

say()  { printf '\n\033[1;36m[field] %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }

# [c] always show remaining space on the capture SSD(s) at every run — a full
# disk kills the rx writer AND git pulls (Yi, 2026-07-28)
for _v in /Volumes/USRP*; do
  [ -d "$_v" ] || continue
  df -h "$_v" | awk -v v="$_v" 'NR==2{printf "  \033[1;35m⛁ %s: %s free\033[0m of %s (%s used)\n", v, $4, $2, $5}'
done

# ── conda + tmux (resolved lazily; only some commands need them) ──────────────
CONDA_SH=""
for d in "$HOME/miniconda3" "$HOME/miniforge3" "$HOME/anaconda3"; do
  [ -f "$d/etc/profile.d/conda.sh" ] && CONDA_SH="$d/etc/profile.d/conda.sh" && break
done
TMUX_BIN="$(command -v tmux || true)"
[ -z "$TMUX_BIN" ] && [ -x "$HOME/miniconda3/envs/usrp/bin/tmux" ] && TMUX_BIN="$HOME/miniconda3/envs/usrp/bin/tmux"
need_tmux() { [ -n "$TMUX_BIN" ] || { warn "tmux not found. Add it: conda install -n usrp tmux  (or brew install tmux)"; exit 1; }; }
need_conda() { [ -n "$CONDA_SH" ] || { warn "conda not found — run setup-020-usrp-conda-env.sh first"; exit 1; }; }

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

# Spotlight indexing on the capture SSD competes with the RX writer at 50 MS/s
# (overflows) and makes run.sh stop to ask. Disable it on every mounted capture
# volume — done at EACH rx start because macOS can re-enable it after a reboot/
# remount. Needs sudo (you're running field-000-jobs.sh interactively, so fine).
disable_spotlight_capture() {
  local found=0 vol
  for vol in /Volumes/USRP* "${CAPTURE_VOL:-}"; do
    [ -n "$vol" ] && [ -d "$vol" ] || continue
    found=1
    if mdutil -s "$vol" 2>/dev/null | tail -1 | grep -qi enabled; then
      warn "Spotlight ON for $vol — disabling (sudo)…"
      sudo mdutil -i off "$vol" >/dev/null 2>&1 && ok "Spotlight off: $vol" \
        || warn "couldn't disable; run:  sudo mdutil -i off \"$vol\""
    else
      ok "Spotlight already off: $vol"
    fi
  done
  [ "$found" = 1 ] || warn "no capture SSD mounted (/Volumes/USRP* or \$CAPTURE_VOL) — skipping Spotlight step"
}

# [c] Always ask the RX center frequency at each rx start (Yi, 2026-07-28).
# Enter keeps the run.conf FREQ; RX_FREQ=… pre-answers (also the no-tty path).
# Result in RX_FREQ_HZ (global — the caller runs under $(), so no echo/capture).
RX_FREQ_HZ=""
ask_rx_freq() {
  local conf_freq; conf_freq="$(sed -n 's/^FREQ=\([^ ]*\).*/\1/p' "$RX_DIR/run.conf" 2>/dev/null | head -1)"
  RX_FREQ_HZ="${RX_FREQ:-}"
  if [ -z "$RX_FREQ_HZ" ] && [ ! -t 0 ]; then
    warn "no tty to ask RX center freq — using run.conf FREQ=${conf_freq:-?} (set RX_FREQ to choose)"
    RX_FREQ_HZ="$conf_freq"; return 0
  fi
  while [ -z "$RX_FREQ_HZ" ]; do
    printf '  RX center frequency in Hz [%s]: ' "${conf_freq:-run.conf default}"
    read -r RX_FREQ_HZ
    [ -z "$RX_FREQ_HZ" ] && RX_FREQ_HZ="$conf_freq"
    case "$RX_FREQ_HZ" in
      ''|*[!0-9.eE+-]*) warn "'$RX_FREQ_HZ' doesn't look like a frequency in Hz (e.g. 2.44e9)"; RX_FREQ_HZ="" ;;
    esac
  done
}

# [c] sync this mini's clock through the operator tunnel — off-grid there is
# no NTP and a drifted clock breaks --start scheduling. UDP NTP can't ride a
# SOCKS tunnel, so use an HTTPS Date header (±1 s, plenty). Only sets the
# clock (sudo) when drift ≥ 2 s. (Yi, 2026-07-28)
sync_time_via_tunnel() {
  local hdr remote_epoch drift before
  hdr="$(curl -sI -m 5 -x socks5h://127.0.0.1:1080 https://www.google.com 2>/dev/null | sed -n 's/^[Dd]ate: //p' | tr -d '\r')"
  [ -z "$hdr" ] && { warn "time sync skipped — tunnel not up (clock unchecked; off-grid it may drift)"; return 0; }
  remote_epoch="$(date -j -u -f '%a, %d %b %Y %H:%M:%S GMT' "$hdr" +%s 2>/dev/null)"
  [ -z "$remote_epoch" ] && { warn "time sync skipped — couldn't parse '$hdr'"; return 0; }
  drift=$((remote_epoch - $(date +%s)))
  if [ "$drift" -lt 2 ] && [ "$drift" -gt -2 ]; then
    ok "clock OK (drift ${drift}s vs internet time, via tunnel)"
  else
    before="$(date '+%H:%M:%S')"
    if sudo date -u -f '%a, %d %b %Y %H:%M:%S GMT' "$hdr" >/dev/null 2>&1; then
      ok "clock was ${drift}s off — synced via tunnel: $before → $(date '+%H:%M:%S') local"
    else
      warn "clock is ${drift}s off but couldn't set it (sudo date failed) — fix manually"
    fi
  fi
}

# [c] after the freq prompt, ask an optional deferred start (run.sh --start).
# Enter = start now. HH:MM local; a past time = tomorrow (confirmed here, and
# run.sh auto-defers non-interactively since its stdin is /dev/null in tmux).
# RX_START=HH:MM (or "now") pre-answers.
RX_START_HHMM=""
ask_rx_start() {
  local t="${RX_START:-}" ans now_m t_m
  [ "$t" = "now" ] && t=""
  if [ ! -t 0 ]; then RX_START_HHMM="$t"; return 0; fi
  while :; do
    if [ -z "$t" ]; then
      printf '  RX start time HH:MM local [Enter = start now]  (machine time now: %s): ' "$(date '+%H:%M')"
      read -r t
      [ -z "$t" ] && { RX_START_HHMM=""; return 0; }
    fi
    case "$t" in
      [0-9]:[0-5][0-9]|[0-1][0-9]:[0-5][0-9]|2[0-3]:[0-5][0-9])
        now_m=$((10#$(date +%H) * 60 + 10#$(date +%M)))
        t_m=$((10#${t%%:*} * 60 + 10#${t##*:}))
        if [ "$t_m" -le "$now_m" ]; then
          printf '  ! %s already passed today — start TOMORROW at %s? [y = tomorrow / Enter = re-enter]: ' "$t" "$t"
          read -r ans
          case "$ans" in [yY]*) RX_START_HHMM="$t"; return 0 ;; *) t=""; continue ;; esac
        fi
        RX_START_HHMM="$t"; return 0 ;;
      *) warn "'$t' doesn't look like HH:MM (e.g. 18:30)"; t="" ;;
    esac
  done
}

start_one() {
  case "$1" in
    rtk)
      [ -z "$RTK_DIR" ] && { warn "RTK_dev_for_cm-loc not found (set REPO_BASE)"; return 1; }
      "$TMUX_BIN" has-session -t rtk 2>/dev/null && { ok "rtk already running (attach: ./field-000-jobs.sh attach rtk)"; return 0; }
      local port="${RTK_PORT:-$(ls /dev/cu.usbmodem* 2>/dev/null | head -1)}"
      [ -z "$port" ] && warn "no /dev/cu.usbmodem* found — plug in the rover, or set RTK_PORT"
      local web="${RX_WEBPORT:-8000}"
      local cmd="python relposned_monitor.py --mode web --host 0.0.0.0 --web-port $web --port ${port:-/dev/cu.usbmodem212301}"
      "$TMUX_BIN" new-session -d -s rtk "$(wrap "$RTK_DIR" "$cmd" "$LOGDIR/rtk.log")"
      ok "rtk started → web dashboard at http://<this-mac-ip>:$web  (log: $LOGDIR/rtk.log)" ;;
    rx)
      [ -z "$RX_DIR" ] && { warn "USRP 01-rx-to-ssd-b200-agc not found (set REPO_BASE)"; return 1; }
      "$TMUX_BIN" has-session -t rx 2>/dev/null && { ok "rx already running (attach: ./field-000-jobs.sh attach rx)"; return 0; }
      disable_spotlight_capture   # so run.sh doesn't block on the Spotlight prompt / overflow
      ask_rx_freq                 # [c] confirm center freq every start; --freq overrides run.conf
      ask_rx_start                # [c] optional deferred start (run.sh --start)
      local freq_args=""
      [ -n "$RX_FREQ_HZ" ] && freq_args=" --freq $RX_FREQ_HZ"
      [ -n "$RX_START_HHMM" ] && freq_args="$freq_args --start $RX_START_HHMM${RX_START_TZ:+ --start-tz $RX_START_TZ}"
      # run.sh respects the active conda env; FORCE_RUN=1 is a non-tty fallback.
      # stdin </dev/null so no run.sh prompt can ever hang the detached pane.
      "$TMUX_BIN" new-session -d -s rx "$(wrap "$RX_DIR" "FORCE_RUN=1 ./run.sh$freq_args </dev/null" "$LOGDIR/rx.log")"
      ok "rx started (freq ${RX_FREQ_HZ:-run.conf default} Hz${RX_START_HHMM:+, deferred to $RX_START_HHMM}) → 01-rx-to-ssd-b200-agc/run.sh  (log: $LOGDIR/rx.log)" ;;
    *) warn "unknown job '$1' (use rtk or rx)"; return 1 ;;
  esac
}

case "$CMD" in
  start)
    need_tmux; need_conda
    say "Starting field jobs in tmux (survive SSH disconnect)"
    sync_time_via_tunnel        # [c] clock sanity before any timed start
    if [ -n "$TARGET" ]; then start_one "$TARGET"; else start_one rtk; start_one rx; fi
    say "Reconnect later, then:  ./field-000-jobs.sh attach rx   (or rtk) ·  ./field-000-jobs.sh logs rx" ;;
  attach)
    need_tmux; [ -z "$TARGET" ] && { warn "which? ./field-000-jobs.sh attach rx|rtk"; exit 1; }
    exec "$TMUX_BIN" attach -t "$TARGET" ;;
  logs)
    [ -z "$TARGET" ] && { warn "which? ./field-000-jobs.sh logs rx|rtk"; exit 1; }
    exec tail -f "$LOGDIR/$TARGET.log" ;;
  status)
    need_tmux; say "tmux sessions"; "$TMUX_BIN" ls 2>/dev/null || echo "  (none)"
    say "logs in $LOGDIR"; ls -la "$LOGDIR" 2>/dev/null ;;
  stop)
    need_tmux
    if [ -n "$TARGET" ]; then "$TMUX_BIN" kill-session -t "$TARGET" 2>/dev/null && ok "stopped $TARGET" || warn "no session $TARGET";
    else for s in rtk rx; do "$TMUX_BIN" kill-session -t "$s" 2>/dev/null && ok "stopped $s"; done; fi ;;
  *)
    # [c] print the whole header comment block (stops at the first non-# line,
    # so it survives header growth — the old fixed 2,30p range leaked code)
    awk 'NR==1{next} !/^#/{exit} {sub(/^# ?/,""); print}' "${BASH_SOURCE[0]}" ;;
esac
