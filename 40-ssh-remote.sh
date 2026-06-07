#!/usr/bin/env bash
# 40-ssh-remote.sh — let other people remote into this Mac.
#   * SSH (Remote Login / sshd) for terminal access
#   * Screen Sharing (VNC) for GUI control — GRC, Jupyter, MATLAB need a display
#
# Needs sudo. Some of this is gated by macOS privacy (TCC): if a command is
# refused, grant the Terminal app "Full Disk Access" in
# System Settings ▸ Privacy & Security ▸ Full Disk Access, then re-run.
set -u

say()  { printf '\n\033[1;36m[40] %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }

[ "$(id -u)" -eq 0 ] && { warn "Run as your normal user (it calls sudo itself), not as root."; exit 1; }

# ── 1. SSH / Remote Login ─────────────────────────────────────────────────────
say "Enabling SSH (Remote Login)"
if sudo systemsetup -getremotelogin 2>/dev/null | grep -qi 'On'; then
  ok "Remote Login already On"
else
  sudo systemsetup -setremotelogin on 2>/dev/null \
    && ok "Remote Login enabled" \
    || warn "Could not enable via systemsetup — grant Terminal Full Disk Access (see header) or toggle 'Remote Login' in System Settings ▸ General ▸ Sharing."
fi

# ── 2. Screen Sharing (VNC) ───────────────────────────────────────────────────
# Screen Sharing and Remote Management (ARD) CONFLICT — only one can be active.
# A bare `launchctl enable` can leave Screen Sharing in a "not permitted" half-
# state (VNC then fails). So: turn OFF Remote Management first, then do a clean
# bootout + bootstrap of Screen Sharing.
say "Enabling Screen Sharing (GUI / VNC)"
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
     -deactivate -stop >/dev/null 2>&1 || true   # ensure Remote Management is OFF (conflicts)
sudo launchctl enable system/com.apple.screensharing 2>/dev/null || true
sudo launchctl bootout   system /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true
if sudo launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null; then
  ok "Screen Sharing (re)started clean"
else
  warn "Couldn't start via launchctl. In System Settings ▸ General ▸ Sharing:"
  warn "turn Screen Sharing OFF then ON, and make sure Remote Management is OFF."
fi
warn "If VNC says 'Screen Sharing is not permitted', re-run those 3 launchctl lines"
warn "(or toggle Screen Sharing off/on in System Settings) — it's the ARD conflict."
warn "Remote users log in with a local macOS account + that account's password."

# ── 3. SSH key access for collaborators ───────────────────────────────────────
say "SSH key access"
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
touch "$HOME/.ssh/authorized_keys" && chmod 600 "$HOME/.ssh/authorized_keys"
ok "~/.ssh/authorized_keys ready"
warn "Add each collaborator's PUBLIC key (one per line) to ~/.ssh/authorized_keys:"
printf '    echo "ssh-ed25519 AAAA... them@host" >> ~/.ssh/authorized_keys\n'
warn "Password SSH login also works for any local account (keys are just safer)."

# ── 4. How to reach this Mac ──────────────────────────────────────────────────
say "Connection info — give this to whoever connects"
USERN="$(whoami)"
HOSTN="$(scutil --get LocalHostName 2>/dev/null).local"
IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo '<run: ipconfig getifaddr en0>')"
ok "user:        $USERN"
ok "hostname:    $HOSTN"
ok "IP (LAN):    $IP"
printf '\n  SSH:           \033[1mssh %s@%s\033[0m   (or ssh %s@%s)\n' "$USERN" "$IP" "$USERN" "$HOSTN"
printf '  Screen share:  \033[1mvnc://%s\033[0m   (Finder ▸ Go ▸ Connect to Server, or the Screen Sharing app)\n' "$IP"
warn "For access from OUTSIDE the LAN you also need router port-forwarding/VPN (out of scope here)."
say "Done."
