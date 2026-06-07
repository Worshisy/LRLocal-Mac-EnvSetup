# Mac mini Headless Field Setup Runbook

> **Review status:** ⏳ Unreviewed *(default; update when Yi reviews)*
>
> ✍️ *Claude-authored summary (from Yi's field-setup Q/A).* The scriptable parts
> are automated by [`../80-hotspot.sh`](../80-hotspot.sh); the GUI/sensitive
> steps (FileVault off, auto-login, the Internet-Sharing AP SSID/password) are
> manual and walked through here. **Run once with a display attached, and pass
> the Phase-3 reboot tests before going to the field.**

**Goal:** Mac mini boots → auto-logs in → Wi-Fi AP comes up → laptop joins and SSH works, all without keyboard or display in the field.

**Architecture:** The Mac mini broadcasts its own Wi-Fi access point (via macOS Internet Sharing) with no internet uplink. The laptop joins this AP and SSHes to the mini at `192.168.2.1`. A "dummy uplink" (Ethernet loopback plug, tiny USB switch, or just a known disconnected interface) gives macOS the link it needs to start Internet Sharing.

> **`80-hotspot.sh` automates:** Wi-Fi cleanup (§1.6), never-sleep + auto-restart
> (§1.4–1.5), disable updates (§1.9), and the sharing-restart LaunchDaemon (§1.8).
> **You still do by hand:** FileVault off (§1.1), auto-login (§1.3), and the
> Internet Sharing AP config (§1.7). SSH (§1.2) is step 40 of the main kit.

---

## 0. What you bring to the field

- Mac mini + AC adapter (or large USB-PD battery if running off-grid)
- One of: Ethernet loopback plug (~$5), tiny USB-powered switch (~$12), or USB-Ethernet adapter with a short cable looped back
- Laptop with Wi-Fi
- Backup plan: short Ethernet cable + adapter for direct laptop ↔ mini if the AP fails

---

## Phase 1 — One-time Mac mini setup (with display attached)

Do all of this while the mini still has a monitor and keyboard. Test before unplugging.

### 1.1 Disable FileVault
System Settings → Privacy & Security → FileVault → Turn Off. Wait for decryption to finish (can take an hour).
```bash
fdesetup status          # expected: FileVault is Off.
```
FileVault must be off for auto-login. With it on, the mini can't survive a power loss — it sits at the pre-boot recovery screen forever.

### 1.2 Enable SSH server
System Settings → General → Sharing → toggle **Remote Login** on. *(Main kit step 40.)*
```bash
sudo systemsetup -getremotelogin    # expected: Remote Login: On
```

### 1.3 Set auto-login
System Settings → Users & Groups → at the **bottom of the main page**, "**Automatically log in as**" → pick your user, enter password. (It's on the main page, not the per-user popup.) If missing, FileVault is still on or "Use Apple Account password to log in" is enabled (turn that off).
```bash
defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser   # expected: your username
# CLI fallback:
sudo sysadminctl -autologin set -userName "yishen" -password -
```

### 1.4 Never sleep, never display sleep   *(automated by 80-hotspot.sh)*
```bash
sudo pmset -a sleep 0 displaysleep 0 disksleep 0
sudo pmset -a powernap 0 standby 0 hibernatemode 0
pmset -g                 # expect: sleep 0, displaysleep 0, disksleep 0
```

### 1.5 Auto-restart on power failure   *(automated by 80-hotspot.sh)*
```bash
sudo pmset -a autorestart 1
sudo systemsetup -setrestartfreeze on
sudo systemsetup -setrestartpowerfailure on
```
Also confirm System Settings → Energy → "Start up automatically after a power failure" is checked.

### 1.6 Wi-Fi cleanup (critical for field reliability)   *(automated by 80-hotspot.sh)*
If the mini auto-joins any known SSID at boot, the AP cannot start. Remove all preferred networks (use your actual Wi-Fi device — `en0` or `en1`):
```bash
networksetup -listpreferredwirelessnetworks en0
for n in $(networksetup -listpreferredwirelessnetworks en0 | tail -n +2 | sed 's/^[[:space:]]*//'); do
  sudo networksetup -removepreferredwirelessnetwork en0 "$n"
done
networksetup -setairportpower en0 on
```

### 1.7 Configure Internet Sharing (the Wi-Fi AP)   *(manual GUI)*
**Prereqs:** built-in Ethernet has **no real internet** — a loopback/dead switch is fine (it needs *link*, not internet). If a campus 802.1X cable is plugged in, **unplug it** (macOS refuses to share an 802.1X source).

System Settings → General → Sharing → ⓘ next to **Internet Sharing**:
- **Share your connection from:** Ethernet
- **To devices using:** check Wi-Fi
- **Wi-Fi Options:** Name `macmini-field` · **Channel 40 (5 GHz)** · Security **WPA2/WPA3 Personal** · Password **`eecs2435`**
  - *Channel 40 is 5 GHz. macOS Internet Sharing on Apple Silicon is often 2.4 GHz-only — if the GUI won't show ch 40 / 5 GHz, use a 2.4 GHz channel (e.g. 11) instead.*

Click Done, toggle **Internet Sharing** on → Start.
```bash
ifconfig | grep -A 3 "^bridge"     # expect bridge100 with inet 192.168.2.1
ps aux | grep -E "bootpd|InternetSharing" | grep -v grep
```
Menu bar shows the upward AP arrow. From the laptop, **confirm the lock icon** on the SSID — there's a macOS bug where the password silently fails (network shows open). If unlocked, toggle Sharing off/on once.

### 1.8 Make Internet Sharing survive reboots   *(automated by 80-hotspot.sh)*
The toggle persists but the AP often fails to broadcast after a cold boot. A LaunchDaemon kicks it 30 s after boot:
```bash
sudo tee /Library/LaunchDaemons/com.local.sharing-restart.plist > /dev/null <<'EOF'
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
sudo launchctl load -w /Library/LaunchDaemons/com.local.sharing-restart.plist
```

### 1.9 Disable disruptions   *(automated by 80-hotspot.sh)*
```bash
sudo softwareupdate --schedule off
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool false
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false
```

### 1.10 Note credentials (for the field bag)
mini username · mini login password · SSH target `192.168.2.1` ·
**AP SSID `macmini-field` · AP channel 40 (5 GHz) · AP password `eecs2435`**.

---

## Phase 2 — Laptop SSH setup

### 2.1 macOS/Linux laptop
```bash
cat >> ~/.ssh/config <<'EOF'

Host mini
    HostName 192.168.2.1
    User yishen
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 4
EOF
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519        # if you don't have a key
ssh-copy-id -i ~/.ssh/id_ed25519.pub mini          # once, over the AP
ssh mini "hostname; uptime; whoami"
```

### 2.2 Windows (PowerShell) — config at `C:\ssh\ssh_config.txt`
```powershell
Add-Content -Path "C:\ssh\ssh_config.txt" -Value @"

Host mini
    HostName 192.168.2.1
    User yishen
    IdentityFile C:\ssh\id_ed25519
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 4
"@
# default ssh to this config:
function ssh { & ssh.exe -F "C:\ssh\ssh_config.txt" @args }   # add to $PROFILE
ssh-keygen -t ed25519 -f C:\ssh\id_ed25519
type C:\ssh\id_ed25519.pub | ssh -F C:\ssh\ssh_config.txt mini "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
icacls C:\ssh\id_ed25519 /inheritance:r /grant:r "$($env:USERNAME):F"
ssh mini "hostname; uptime; whoami"
```

---

## Phase 3 — Reboot tests (before leaving)

```bash
sudo shutdown -r now
```
No keyboard touch — the mini should: (1) boot to desktop (auto-login), (2) Wi-Fi icon → upward AP arrow within ~30 s (sharing-restart), (3) laptop sees SSID and `ssh mini` works.

**Power-failure test:** pull the cord while running, wait 10 s, plug back in → same sequence. If it stays dark, `autorestart` isn't engaged (re-check §1.5).

**Checklist:** clean-reboot pass · power-cycle pass · SSH key (no prompt) · loopback/switch packed · power adapter (+ battery) packed · credentials recorded offline · backup direct-Ethernet cable + adapter packed.

---

## Troubleshooting

- **"...protected by 802.1X"** — the source interface is authenticated (campus). Unplug the Ethernet cable; `sudo ifconfig en0 down` (Wi-Fi); or use a USB-Ethernet adapter with nothing on the far end.
- **AP not visible** — `networksetup -getairportpower <wifi-dev>`; `ifconfig | grep -A3 '^bridge'` (bridge100 192.168.2.1?); `ps aux | grep -E 'bootpd|InternetSharing'`; logs: `log show --last 2m --predicate 'subsystem == "com.apple.NetworkSharing"' --info --debug | tail -50`. Force: `sudo launchctl kickstart -k system/com.apple.InternetSharing`.
- **Toggle won't enable** — the source needs *link*: plug in a loopback/powered switch/USB-Ethernet.
- **`# is not a valid command` when pasting** — zsh interactive comments: `echo 'setopt interactive_comments' >> ~/.zshrc; source ~/.zshrc`.
- **SSH refused** — `sudo systemsetup -getremotelogin` (On?); `sudo launchctl list | grep ssh`; toggle Remote Login off/on.
- **AP up but no DHCP** — `sudo killall bootpd; sudo launchctl kickstart -k system/com.apple.InternetSharing`.

## Field operation notes
- Throughput: 2.4 GHz only on Apple Silicon, ~20–40 Mbps — fine for SSH/small transfers; use direct Ethernet for bulk IQ at end of day.
- Range ~10 m line of sight, less through walls/foliage — keep the laptop close.
- Battery: ~100 Wh USB-PD → ~3–5 h runtime.
- Multiple clients OK. **Avoid rebooting in the field** — rely on `pmset autorestart` + never-sleep.
