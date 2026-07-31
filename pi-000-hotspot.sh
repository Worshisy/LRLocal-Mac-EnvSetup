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
# [c] gitpull / txfreq / shortcuts (Yi, 2026-07-31). Strip by stable prefix →
# re-runs and renames replace the block, never duplicate it.
say "Installing field helpers (gitpull / txfreq / shortcuts) into ~/.bashrc"
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
txfreq() {  # txfreq → show; txfreq 2.55 → set 2.55 GHz (≥1e6 = Hz) in 11-tx run.conf
  local conf="$HOME/USRP_study_yishen/11-tx-beacon-usrpb200-code/run.conf" hz
  [ -f "$conf" ] || { echo "run.conf not found: $conf"; return 1; }
  if [ $# -eq 0 ]; then grep -n '^FREQ=' "$conf"; echo "(change:  txfreq 2.55   = 2.55 GHz)"; return 0; fi
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
alias txstatus='~/USRP_study_yishen/11-tx-beacon-usrpb200-code/deploy/tx-status.sh'
shortcuts() {
  cat <<'MENU'
Pi field shortcuts:
  gitpull       pull the newest USRP_study_yishen (offline OK — rides the SSH tunnel)
  txfreq        show the TX center frequency (11-tx run.conf)
  txfreq 2.55   set it to 2.55 GHz (GHz by default; ≥1e6 = Hz) AND restart the
                tx-beacon service so it's live immediately
  txstatus      TX beacon service status (deploy/tx-status.sh)
  shortcuts     print this list
MENU
}
case $- in *i*) shortcuts ;; esac   # remind at every login
# <<< LRLocal field pi helpers <<<
PIBLOCK
ok "gitpull / txfreq / shortcuts in ~/.bashrc (new shells; or:  source ~/.bashrc)"

say "Done. From the laptop:"
printf '  join Wi-Fi \033[1m%s\033[0m (pw %s), then:  \033[1mssh ddh-pi4-beacon\033[0m  (= user@%s;\n' "$AP_SSID" "$AP_PASS" "$AP_IP"
printf '  the shortcut comes from host-000-ssh-config.sh on the laptop)\n'
printf '  Survives reboot (autoconnect). Remove with:  sudo nmcli con delete %s\n' "$CON"
