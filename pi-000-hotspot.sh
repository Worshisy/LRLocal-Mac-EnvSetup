#!/usr/bin/env bash
# pi-000-hotspot.sh — make the TX Raspberry Pi a standalone field Wi-Fi AP
# with SSH login, mirroring the Mac-mini field APs. RUN THIS ON THE PI
# (copy it over first:  scp pi-000-hotspot.sh user@<pi-ip>: ).
#
#   SSID ddh-pi4-beacon · pw eecs2435 · ch 40 (5 GHz) · Pi at 192.168.3.1
#   (…3.1, NOT the minis' …2.1 — distinct subnet, no host-key/DHCP ambiguity)
#
# Touches ONLY wlan0 + sshd — the USRP TX setup (11-tx-beacon-usrpb200-code)
# and eth0 are left alone; at home the Pi keeps internet over Ethernet.
# Needs NetworkManager (Raspberry Pi OS Bookworm default) and sudo.
# Idempotent: re-run to reapply; overrides:
#   AP_SSID=… AP_PASS=… AP_IP=… AP_BAND=a|bg AP_CHAN=…  WIFI_COUNTRY=US
#   AP_BAND=bg AP_CHAN=6   ← 2.4 GHz fallback if a client can't see 5 GHz
set -u

say()  { printf '\n\033[1;36m[pi-ap] %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }

AP_SSID="${AP_SSID:-ddh-pi4-beacon}"
AP_PASS="${AP_PASS:-eecs2435}"
AP_IP="${AP_IP:-192.168.3.1}"
AP_BAND="${AP_BAND:-a}"          # a = 5 GHz, bg = 2.4 GHz
AP_CHAN="${AP_CHAN:-40}"
WIFI_COUNTRY="${WIFI_COUNTRY:-US}"
CON=pi-field-ap                  # NetworkManager connection name

[ "$(uname)" = "Linux" ] || { warn "run this ON the Raspberry Pi, not the Mac"; exit 1; }
command -v nmcli >/dev/null 2>&1 || {
  warn "nmcli not found — this script needs NetworkManager (Raspberry Pi OS"
  warn "Bookworm or newer). On older Bullseye images, update the OS first."
  exit 1
}

# ── 1. SSH server on ──────────────────────────────────────────────────────────
say "Enabling SSH"
sudo systemctl enable --now ssh >/dev/null 2>&1 && ok "sshd enabled + running" \
  || warn "couldn't enable ssh via systemctl — enable it in raspi-config"

# ── 2. Wi-Fi regulatory domain (required before AP mode works) ────────────────
say "Wi-Fi country → $WIFI_COUNTRY"
if command -v raspi-config >/dev/null 2>&1; then
  sudo raspi-config nonint do_wifi_country "$WIFI_COUNTRY" >/dev/null 2>&1 \
    && ok "country set via raspi-config" || warn "raspi-config country set failed"
else
  sudo iw reg set "$WIFI_COUNTRY" 2>/dev/null && ok "country set via iw" || warn "iw reg set failed"
fi
sudo rfkill unblock wifi 2>/dev/null || true

# ── 3. The AP connection (replaces any previous run of this script) ───────────
say "Configuring AP: SSID $AP_SSID @ $AP_IP (band $AP_BAND ch $AP_CHAN)"
# Bringing the AP up DROPS any Wi-Fi *client* connection on wlan0. If your SSH
# session rides that Wi-Fi, you'll be cut off — reconnect by joining $AP_SSID.
if nmcli -t -f DEVICE,TYPE,STATE device | grep -q '^wlan0:wifi:connected'; then
  warn "wlan0 is currently a Wi-Fi CLIENT — switching it to AP mode will drop"
  warn "that connection (SSH over it included). Ethernet sessions are safe."
  if [ -t 0 ] && [ "${PI_AP_YES:-0}" != "1" ]; then
    printf '  continue? [y/N]: '; read -r _a
    case "$_a" in [yY]*) ;; *) warn "aborted — nothing changed."; exit 1 ;; esac
  fi
fi
sudo nmcli con delete "$CON" >/dev/null 2>&1 || true
sudo nmcli con add type wifi ifname wlan0 con-name "$CON" autoconnect yes \
     ssid "$AP_SSID" mode ap >/dev/null
sudo nmcli con modify "$CON" \
     802-11-wireless.band "$AP_BAND" 802-11-wireless.channel "$AP_CHAN" \
     802-11-wireless.powersave 2 \
     802-11-wireless-security.key-mgmt wpa-psk \
     802-11-wireless-security.psk "$AP_PASS" \
     ipv4.method shared ipv4.addresses "$AP_IP/24" \
     ipv6.method disabled \
     connection.autoconnect-priority 999
if sudo nmcli con up "$CON" >/dev/null 2>&1; then
  ok "AP up: SSID $AP_SSID · pw $AP_PASS · this Pi = $AP_IP"
else
  warn "AP failed on band $AP_BAND ch $AP_CHAN — retrying on 2.4 GHz (bg/6)…"
  sudo nmcli con modify "$CON" 802-11-wireless.band bg 802-11-wireless.channel 6
  sudo nmcli con up "$CON" >/dev/null 2>&1 && ok "AP up on 2.4 GHz: $AP_SSID @ $AP_IP" \
    || { warn "AP still failing — check:  nmcli device; journalctl -u NetworkManager -e"; exit 1; }
fi

# ── 4. Field helper aliases into ~/.bashrc ────────────────────────────────────
# [c] gitpull / tx_freq / shortcuts (Yi, 2026-07-31). Strip by stable prefix →
# re-runs and renames replace the block, never duplicate it.
say "Installing field helpers (gitpull / tx_freq / …) into ~/.bashrc"
# [c] passwordless sudo for /usr/bin/date ONLY — the login clock-sync must not
# prompt. Validated with visudo before install (a bad sudoers.d breaks sudo).
echo "$USER ALL=(root) NOPASSWD: /usr/bin/date" > /tmp/lrlocal-timesync
if visudo -cf /tmp/lrlocal-timesync >/dev/null 2>&1; then
  sudo install -m 0440 /tmp/lrlocal-timesync /etc/sudoers.d/lrlocal-timesync \
    && ok "sudoers: passwordless 'date' for login time-sync"
else
  warn "sudoers rule failed validation — login sync will only report drift"
fi
rm -f /tmp/lrlocal-timesync

# ── [c] shared time-sync script + every-ssh-connection hook ──────────────────
# lrl-timesync.sh is called by BOTH the interactive login hook in .bashrc
# (with -f = always fetch) and ~/.ssh/rc on every ssh/scp connection
# (throttled to one attempt / 10 min, silent). The no-internet case is covered
# from the operator side: host-000's LocalCommand pushes the PC clock on every
# connection (gated at >=2 s drift), so internet sync here + host push there
# together keep the Pi clock honest in all field conditions.
mkdir -p "$HOME/bin" "$HOME/.ssh" "$HOME/field-logs"
cat > "$HOME/bin/lrl-timesync.sh" <<'TSYNC'
#!/bin/bash
# tunnel time-sync — shared by the interactive login hook (bashrc, -f) and the
# every-ssh-connection hook (~/.ssh/rc, throttled). Source: internet Date
# header via the operator's reverse SOCKS tunnel. No internet? The operator
# side pushes its own clock instead (host-000 LocalCommand) — not our job.
STAMP=/tmp/.lrl-timesync-attempt
(exec 3<>/dev/tcp/127.0.0.1/1080) 2>/dev/null || { echo "[time] no tunnel — clock unchecked"; exit 0; }
if [ "$1" != "-f" ] && [ -e "$STAMP" ]; then
  age=$(( $(date +%s) - $(stat -c %Y "$STAMP" 2>/dev/null || echo 0) ))
  [ "$age" -ge 0 ] && [ "$age" -lt 600 ] && { echo "[time] attempted <10 min ago — skipped"; exit 0; }
fi
touch "$STAMP"
hdr=$(curl -sI -m 4 -x socks5h://127.0.0.1:1080 https://www.google.com 2>/dev/null | sed -n 's/^[Dd]ate: //p' | tr -d '\r')
[ -z "$hdr" ] && { echo "[time] tunnel up but time fetch failed — clock unchecked (host push covers this)"; exit 0; }
rs=$(date -ud "$hdr" +%s 2>/dev/null) || exit 0
drift=$(( rs - $(date +%s) ))
if [ "${drift#-}" -lt 2 ]; then echo "[time] clock OK (drift ${drift}s vs internet)"
elif sudo -n date -us "@$rs" >/dev/null 2>&1; then echo "[time] clock was ${drift}s off — SYNCED via tunnel"; touch "$STAMP"
else echo "[time] clock ${drift}s off — couldn't set; run:  sudo date -us @$rs"
fi
TSYNC
chmod +x "$HOME/bin/lrl-timesync.sh"
cat > "$HOME/.ssh/rc" <<'SSHRC'
# LRLocal: opportunistic clock sync on EVERY ssh connection (the operator's
# ssh always carries the reverse tunnel). MUST stay silent — any stdout here
# corrupts scp/sftp. Backgrounded so sessions are never delayed.
( "$HOME/bin/lrl-timesync.sh" >/dev/null 2>&1 & )
SSHRC
chmod 600 "$HOME/.ssh/rc"
ok "time-sync: ~/bin/lrl-timesync.sh + ~/.ssh/rc hook (fires on every ssh/scp)"

# ── [c] web file browser over $HOME at :8082 (like the minis' "files" job) ───
# No passwordless sudo for systemd units on the Pi → cron-supervised instead
# (@reboot + a 5-min ensure-alive guard; self-heals after crashes too).
cat > "$HOME/bin/lrl-filebrowser-ensure.sh" <<'FBROW'
#!/bin/bash
# keep the :8082 web file browser alive (cron-driven; serves $HOME, read-only)
pgrep -f "http.server 8082" >/dev/null && exit 0
mkdir -p /home/user/field-logs
setsid -f bash -c "exec python3 -u -m http.server 8082 -d /home/user >> /home/user/field-logs/files.log 2>&1"
FBROW
chmod +x "$HOME/bin/lrl-filebrowser-ensure.sh"
( crontab -l 2>/dev/null | grep -v lrl-filebrowser ; \
  echo "@reboot sleep 20 && $HOME/bin/lrl-filebrowser-ensure.sh" ; \
  echo "*/5 * * * * $HOME/bin/lrl-filebrowser-ensure.sh" ) | crontab -
"$HOME/bin/lrl-filebrowser-ensure.sh"
ok "file browser: http://$AP_IP:8082 (cron-kept-alive, serving \$HOME)"

BRC="$HOME/.bashrc"; touch "$BRC"
PIH_PREFIX='# >>> LRLocal field pi helpers'
PIH_END='# <<< LRLocal field pi helpers <<<'
TMP="$(mktemp)"
awk -v b="$PIH_PREFIX" -v e="$PIH_END" \
    'index($0,b)==1{skip=1} skip==0{print} index($0,e)==1{skip=0}' "$BRC" > "$TMP"
mv "$TMP" "$BRC"
cat >> "$BRC" <<'PIBLOCK'
# >>> LRLocal field pi helpers (managed by LRLocal-Mac-EnvSetup/pi-000-hotspot.sh) >>>
# Offline-friendly: gitpull rides the operator's reverse SOCKS tunnel that
# every `ssh ddh-pi4-beacon` carries (see FIELD-RUNBOOK §4b).
alias gitpull='GIT_SSH_COMMAND="ssh -o ProxyCommand=\"nc -X 5 -x 127.0.0.1:1080 %h %p\"" git -C ~/USRP_study_yishen pull --ff-only'
tx_freq() {  # tx_freq → show; tx_freq 2.55 → set 2.55 GHz (≥1e6 = Hz) in 11-tx run.conf
  local conf="$HOME/USRP_study_yishen/11-tx-beacon-usrpb200-code/run.conf" hz
  [ -f "$conf" ] || { echo "run.conf not found: $conf"; return 1; }
  if [ $# -eq 0 ]; then grep -n '^FREQ=' "$conf"; echo "(change:  tx_freq 2.55   = 2.55 GHz)"; return 0; fi
  hz=$(awk -v x="$1" 'BEGIN{v=x+0; if (v<1000) v*=1e9; if (v>=70e6 && v<=6e9) printf "%ge9", v/1e9}')
  [ -n "$hz" ] || { echo "bad frequency '$1' — GHz (e.g. 2.55); B200 range 70 MHz–6 GHz"; return 1; }
  sed -i "s/^FREQ=.*/FREQ=$hz/" "$conf" && echo "set: $(grep '^FREQ=' "$conf")   ($conf)"
  # run.conf is read at process start only → restart the TX service (system
  # unit, deploy/README §3) so the new freq is live immediately
  if sudo systemctl restart tx-beacon-b200mini.service; then
    sleep 2; echo "tx-beacon restarted → now: $(pgrep -af tx_beacon | grep -o '\-\-freq [^ ]*' | head -1)"
  else
    echo "! restart failed — run:  sudo systemctl restart tx-beacon-b200mini"
  fi
}
tx_status() {  # health summary, then LIVE TX output (like attach) — Ctrl-C exits
  local proj="$HOME/USRP_study_yishen/11-tx-beacon-usrpb200-code" logdir nerr nwarn state
  logdir="$(ls -td "$proj"/logs/*/ 2>/dev/null | head -1)"
  nerr=$(grep -ciE 'error|fail|except' "$logdir/run.log" 2>/dev/null); nerr=${nerr:-0}
  # 'Unexpected GPSDO string: LC_XO…' = benign B200 startup noise, don't count
  nwarn=$(grep -iE 'warn' "$logdir/run.log" 2>/dev/null | grep -civE 'Unexpected GPSDO string'); nwarn=${nwarn:-0}
  state="$(systemctl is-active tx-beacon-b200mini.service 2>/dev/null)"
  if [ "$state" = "active" ] && [ "$nerr" = "0" ] && [ "$nwarn" = "0" ]; then
    echo "[summary] service ACTIVE · run.log clean (0 errors, 0 warnings) ✓"
  else
    echo "[summary] service ${state^^} · run.log: $nerr error / $nwarn warning line(s) — check: ${logdir}run.log"
  fi
  echo "── live TX output (Ctrl-C to exit; full snapshot: $proj/deploy/tx-status.sh) ──"
  journalctl -fu tx-beacon-b200mini.service -n 15
}
# [c] clock sync at login — thin wrapper; the real logic lives in
# ~/bin/lrl-timesync.sh, shared with the ~/.ssh/rc every-connection hook
# (installed above). -f = skip the 10-min throttle, like the old behavior.
_lrl_timesync() { "$HOME/bin/lrl-timesync.sh" -f; }
alias tx_restart='sudo systemctl restart tx-beacon-b200mini.service && sleep 2 && pgrep -af tx_beacon_b200 | grep -o "\-\-freq [^ ]*" | sed "s/^/tx-beacon restarted → /"'
alias pi_restart='sudo shutdown -r now'   # AP + TX come back on their own (~1 min)
case $- in *i*) _lrl_timesync; cat <<'MENU'
Pi field shortcuts:
  gitpull        pull the newest USRP_study_yishen (offline OK — rides the SSH tunnel)
  tx_freq        show the TX center frequency (11-tx run.conf)
  tx_freq 2.55   set it to 2.55 GHz (GHz by default; ≥1e6 = Hz) AND restart the
                 tx-beacon service so it's live immediately
  tx_status      health summary + LIVE TX output (Ctrl-C to exit)
  tx_restart     restart the TX beacon service (re-reads run.conf)
  pi_restart     reboot the whole Pi (AP + TX auto-return in ~1 min)
  (web)          file browser at http://192.168.3.1:8082 — logs/captures in ~
MENU
esac   # time-synced + printed at every login — no command to remember
# <<< LRLocal field pi helpers <<<
PIBLOCK
ok "gitpull / tx_freq / shortcuts in ~/.bashrc (new shells; or:  source ~/.bashrc)"

say "Done. From the laptop:"
printf '  join Wi-Fi \033[1m%s\033[0m (pw %s), then:  \033[1mssh ddh-pi4-beacon\033[0m  (= user@%s;\n' "$AP_SSID" "$AP_PASS" "$AP_IP"
printf '  the shortcut comes from host-000-ssh-config.sh on the laptop)\n'
printf '  Survives reboot (autoconnect). Remove with:  sudo nmcli con delete %s\n' "$CON"
