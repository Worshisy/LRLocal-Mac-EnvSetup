#!/usr/bin/env bash
# 80-hotspot.sh — turn this Mac into a Wi-Fi hotspot (macOS Internet Sharing).
#
# macOS Internet Sharing shares ONE interface's internet to others. For a Wi-Fi
# HOTSPOT the uplink must be a DIFFERENT (wired) interface — Wi-Fi can't be both
# the uplink and the broadcast radio. So: plug internet into Ethernet/USB-NIC,
# and Wi-Fi becomes the hotspot.
#
# On macOS 26 the SSID/password and the ON toggle are GUI + Keychain + privacy
# (TCC) gated and can't be fully scripted. This script: shows your interfaces,
# configures the scriptable NAT bits (best effort), and walks you through the
# exact GUI steps. Run as your normal user (it calls sudo itself).
#
# NOTE: if your shared Claude Q/A uses a different method, paste it and we'll
# replace this with that exact procedure.
set -u

say()  { printf '\n\033[1;36m[80] %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }

[ "$(id -u)" -eq 0 ] && { warn "Run as your normal user (it calls sudo itself), not as root."; exit 1; }

# ── 1. Show this Mac's interfaces + which has internet ────────────────────────
say "Network interfaces on this Mac"
networksetup -listnetworkserviceorder 2>/dev/null | grep -E 'Hardware Port|Device' | sed 's/^/  /' | head -40
UPLINK_WIFI="$(ipconfig getifaddr en1 2>/dev/null || true)"
[ -n "$UPLINK_WIFI" ] && warn "Internet is currently via Wi-Fi (en1=$UPLINK_WIFI). For a Wi-Fi HOTSPOT you must move the uplink to a WIRED port (en0 Ethernet or en8 USB-NIC)."

# ── 2. Best-effort scripted enable (may still need the GUI toggle) ────────────
say "Best-effort: enabling the Internet Sharing service"
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.nat NAT -dict Enabled -int 1 2>/dev/null && ok "NAT marked enabled in com.apple.nat" || warn "could not write com.apple.nat (TCC?) — use the GUI"
sudo launchctl enable system/com.apple.InternetSharing 2>/dev/null || true
sudo launchctl kickstart -k system/com.apple.InternetSharing 2>/dev/null && ok "InternetSharing service kicked" || warn "service start needs the GUI toggle (below)"

# ── 3. The reliable path — GUI ────────────────────────────────────────────────
say "Set it up in System Settings (the supported, reliable way):"
cat <<'GUI'
  1. Plug the INTERNET source into a WIRED port (Ethernet en0, or the USB NIC en8).
     (Confirm that wired link has internet before continuing.)
  2. System Settings ▸ General ▸ Sharing ▸ click the ⓘ next to "Internet Sharing".
  3. "Share your connection from:"  → the wired uplink (Ethernet / USB 10/100/1000 LAN).
  4. "To computers using:"          → check  Wi-Fi.
  5. Click "Wi-Fi Options…"         → set Network Name (SSID), Security = WPA2/WPA3
     Personal, and the Password. (Stored in Keychain — that's why it's GUI-only.)
  6. Toggle "Internet Sharing" ON   → confirm "Start". The Wi-Fi menu icon shows ⬆.
  Devices can now join your SSID and get internet through this Mac.
GUI
warn "If macOS blocks the toggle, grant the relevant app Full Disk Access (Privacy & Security) or just use the GUI toggle."
say "Done. Verify: another device sees your SSID; or  ifconfig bridge100  shows the shared subnet when ON."
