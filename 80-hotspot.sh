#!/usr/bin/env bash
# 80-hotspot.sh — make this Mac a STANDALONE FIELD Wi-Fi AP (no internet uplink).
#
# Implements the headless field-setup method (full walkthrough + reboot tests in
# docs/field-setup.md). The mini broadcasts its own Wi-Fi AP at 192.168.2.1 via
# macOS Internet Sharing; a laptop joins it and SSHes in — no display/keyboard.
# A "dummy uplink" (Ethernet loopback plug / dead switch / bare USB-Ethernet)
# gives macOS the LINK it needs to start sharing, even with no real internet.
#
# This script does the SCRIPTABLE parts (Wi-Fi cleanup, never-sleep, auto-restart,
# disable updates, the boot-time AP re-kick daemon). The SSID/password + the
# Internet Sharing ON toggle are GUI/Keychain/TCC-gated → guided at the end.
# Run as your NORMAL user (it calls sudo itself). Do it once, with a display
# attached, and run the reboot tests before going to the field.
set -u

say()  { printf '\n\033[1;36m[80] %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }

[ "$(id -u)" -eq 0 ] && { warn "Run as your normal user (it calls sudo itself), not as root."; exit 1; }
say "Caching sudo (enter your password once)…"; sudo -v || { warn "sudo failed; aborting."; exit 1; }

# Detect the Wi-Fi device on THIS Mac (don't assume en0/en1).
WIFI_DEV="$(networksetup -listallhardwareports 2>/dev/null | awk '/Wi-Fi/{getline; print $2; exit}')"
[ -z "$WIFI_DEV" ] && WIFI_DEV=en1
ok "Wi-Fi device: $WIFI_DEV"

# ── 1. Wi-Fi cleanup — don't auto-join any SSID at boot (else the AP can't start)
say "Removing preferred Wi-Fi networks on $WIFI_DEV"
networksetup -listpreferredwirelessnetworks "$WIFI_DEV" 2>/dev/null | tail -n +2 | sed 's/^[[:space:]]*//' | while IFS= read -r n; do
  [ -n "$n" ] && sudo networksetup -removepreferredwirelessnetwork "$WIFI_DEV" "$n" >/dev/null 2>&1 && echo "    - removed: $n"
done
sudo networksetup -setairportpower "$WIFI_DEV" on 2>/dev/null && ok "Wi-Fi powered on (not joined to anything)"

# ── 2. Headless reliability ───────────────────────────────────────────────────
say "Never sleep; auto-restart after power failure"
sudo pmset -a sleep 0 displaysleep 0 disksleep 0 powernap 0 standby 0 hibernatemode 0 2>/dev/null && ok "sleep disabled"
sudo pmset -a autorestart 1 2>/dev/null && ok "autorestart on power"
sudo systemsetup -setrestartpowerfailure on 2>/dev/null || true
sudo systemsetup -setrestartfreeze on 2>/dev/null || true

say "Disabling automatic software updates"
sudo softwareupdate --schedule off 2>/dev/null || true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool false 2>/dev/null || true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false 2>/dev/null || true
ok "auto-updates off"

# Spotlight on the capture SSD competes with the RX writer at 50 MS/s (overflows)
# and makes run.sh stop to ask. Disable it on the capture volume(s). field-jobs.sh
# re-applies this at each RX start in case macOS re-enables it after a reboot.
say "Disabling Spotlight on capture SSD(s) /Volumes/USRP* (+ \$CAPTURE_VOL)"
_sl_found=0
for vol in /Volumes/USRP* "${CAPTURE_VOL:-}"; do
  [ -n "$vol" ] && [ -d "$vol" ] || continue
  _sl_found=1
  sudo mdutil -i off "$vol" >/dev/null 2>&1 && ok "Spotlight off: $vol" || warn "couldn't disable Spotlight on $vol"
done
[ "$_sl_found" = 1 ] || warn "no capture SSD mounted now — field-jobs.sh also disables it at RX start"

# ── 3. Boot-time AP re-kick daemon ────────────────────────────────────────────
# After a cold boot Internet Sharing's toggle persists but the AP often fails to
# actually broadcast. This kicks it 30 s after boot.
say "Installing the sharing-restart LaunchDaemon"
sudo tee /Library/LaunchDaemons/com.local.sharing-restart.plist >/dev/null <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.local.sharing-restart</string>
  <key>RunAtLoad</key><true/>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>-c</string>
    <string>sleep 30; /bin/launchctl kickstart -k system/com.apple.InternetSharing</string>
  </array>
  <key>StandardOutPath</key><string>/var/log/sharing-restart.log</string>
  <key>StandardErrorPath</key><string>/var/log/sharing-restart.log</string>
</dict>
</plist>
EOF
sudo chown root:wheel /Library/LaunchDaemons/com.local.sharing-restart.plist
sudo chmod 644 /Library/LaunchDaemons/com.local.sharing-restart.plist
sudo launchctl load -w /Library/LaunchDaemons/com.local.sharing-restart.plist 2>/dev/null && ok "sharing-restart daemon installed" || warn "daemon load deferred (loads at boot)"

# ── 4. Manual / GUI prerequisites + the AP config ─────────────────────────────
say "Finish these in the GUI (one-time; see docs/field-setup.md for details):"
cat <<GUI
  HEADLESS LOGIN (so it boots to desktop with no keyboard):
    • Turn OFF FileVault:  System Settings ▸ Privacy & Security ▸ FileVault ▸ Off
        (required for auto-login; verify: fdesetup status -> Off)
    • Auto-login:  System Settings ▸ Users & Groups ▸ "Automatically log in as" ▸ your user
        CLI fallback:  sudo sysadminctl -autologin set -userName "$(whoami)" -password -
    • SSH: ensure Remote Login is ON (step 40 / 40-ssh-remote.sh).

  THE Wi-Fi AP (Internet Sharing):
    • Give built-in Ethernet a DUMMY uplink: loopback plug / dead switch / bare
      USB-Ethernet — it needs LINK, not internet. (If a campus 802.1X cable is
      plugged in, UNPLUG it — macOS refuses to share an 802.1X source.)
    • System Settings ▸ General ▸ Sharing ▸ ⓘ next to "Internet Sharing":
        Share your connection from:  Ethernet (the dummy uplink)
        To devices using:            Wi-Fi
        Wi-Fi Options…:  Name=macmini-field  Channel=40  Security=WPA2/WPA3 Personal  Password=eecs2435
        (Channel 40 = 5 GHz. If the GUI won't offer it / only lists 2.4 GHz on
         this Apple-Silicon mini, pick a 2.4 GHz channel like 11 instead.)
    • Toggle "Internet Sharing" ON ▸ Start.  Menu bar shows the upward AP arrow.
    • From the laptop: confirm a LOCK icon on the SSID (known bug: password can
      silently fail, leaving it open — if so, toggle Sharing off/on once).
GUI

# ── 5. Verify ─────────────────────────────────────────────────────────────────
say "Verify (after you toggle Internet Sharing ON):"
echo "    ifconfig | grep -A3 '^bridge'      # expect bridge100 inet 192.168.2.1"
echo "    ps aux | grep -E 'bootpd|InternetSharing' | grep -v grep"
echo "    # laptop then:  ssh <user>@192.168.2.1"
say "Done. Run the reboot + power-fail tests in docs/field-setup.md before the field."
