# Remote Desktop for Apple-Silicon (M-series) Field Minis — macOS 26

> **Review status:** 👀 Glanced *(Yi set this up live on mac-02 2026-08-14/15; procedure verified end-to-end)*
>
> ✍️ *Claude-authored.* Runbook for getting a **visible, persistent** remote desktop
> on a headless Apple-Silicon (M4) field mini, reachable from **both Mac and Windows**.

## TL;DR

| Client | Tool | Notes |
|---|---|---|
| **Mac** | **Screen Sharing.app** (built-in) | Connect to `192.168.2.1` / `ddh-macmini4-0X.local`, log in with the account (`ddh-macmini4-0X` / `eecs2435`). |
| **Windows** | **RustDesk** (installed on the mini) | Client → type the mini's IP `192.168.2.1` in the ID field (direct-IP, offline LAN) → password `eecs2435`. |

Both attach to the mini's **console session**, so closing the viewer leaves all GUI
tasks running. A **HDMI dummy plug must stay plugged in** at all times.

## What does NOT work (and why) — don't waste time here again

- **Generic VNC** (RealVNC / TightVNC / any raw-RFB client, incl. legacy-VNC password
  set via `kickstart -setvnclegacy`) → connects and authenticates, but the framebuffer
  is **pure black** on M-series. Apple Silicon only serves the real composited desktop
  through Screen Sharing.app's private extensions, which no third-party VNC client speaks.
- **Apple-DH auth via a raw client** → auth succeeds, still black. Same reason.
- **`screencapture` over SSH** → `could not create image from display`. That's a
  separate sshd-TCC limitation (sshd has no Screen Recording grant); it does **not**
  indicate the desktop is broken and is unrelated to the VNC-black issue.

## Hardware prerequisite — HDMI dummy plug

- Keep a **4K HDMI dummy plug** (e.g. UGREEN) in the mini permanently. Without it the M4
  won't build a real framebuffer (black / 800×600 / "Screen Sharing unusable").
- Best plugged in **before boot**. If hot-plugged after a headless boot, WindowServer
  may report the display "online" but not composite to it — a **reboot with the plug in**
  fixes it (a `killall WindowServer`/SIGHUP is NOT enough).

## Mac access — Screen Sharing.app

1. **Enable in the GUI:** System Settings → General → Sharing → **Screen Sharing**
   (or **Remote Management**) **ON**.
   - ⚠️ **This must be done in System Settings, not the CLI.** `launchctl enable/bootstrap
     com.apple.screensharing` and `kickstart -activate` run the daemon but do **not** set
     the client-visible policy, so Screen Sharing.app returns
     **"Screen Sharing is not permitted … Disable and re-enable …"** even though the
     server accepts raw RFB connections. Toggling it in System Settings is the only fix.
   - You cannot have **both** Screen Sharing and Remote Management; enabling one takes the
     port from the other. If stuck on "not permitted", toggle it off/on in System Settings.
2. **Bootstrap the GUI once (chicken-and-egg):** the toggle needs a visible screen. Get
   one first via a **physical monitor for 2 min**, or (what worked on mac-02) restart the
   **Remote Management** function in System Settings from any existing screen access.
3. **Connect:** Screen Sharing.app → `192.168.2.1` → account `ddh-macmini4-0X` / `eecs2435`.

## Windows access — RustDesk (offline LAN, direct-IP)

RustDesk uses ScreenCaptureKit (renders M-series correctly, unlike VNC) and has native
Mac + Windows clients. Installed on the mini already; per-machine setup:

1. **Install:** RustDesk macOS **arm64** dmg → `/Applications/RustDesk.app`
   (`xattr -dr com.apple.quarantine` after copying).
2. **Offline config** (already applied; in `~/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml`):
   `direct-server = 'Y'`  and  `rendezvous_server = ''`  → no relay/internet needed.
3. **Grant permissions (one-time, via a Screen Sharing.app session or monitor):**
   System Settings → Privacy & Security → enable **RustDesk** under **Screen & System
   Audio Recording** *and* **Accessibility**; quit+reopen RustDesk after.
4. In RustDesk → **Security** tab: **"Enable direct IP access"** (port `21118`, already on)
   and set a **permanent password** (`eecs2435`). Turn on **Enable Service** for
   unattended / on-boot / persist-on-disconnect.
5. **Connect from Windows:** RustDesk client → put the mini's IP **`192.168.2.1`** in the
   **ID field** (it accepts a direct IP) → password `eecs2435`.

## Persistence on client disconnect (required by the field workflow)

Both tools attach to the macOS **console session** — closing the viewer does **not** end
the session, so GUI tasks keep running. This needs **auto-login ON** (so the console
session is always up) and **FileVault OFF** (else it boots to the FileVault unlock screen
and never reaches the desktop). Field minis are configured this way.

## Per-machine registry

| mini | dummy plug | RustDesk ID | direct-IP pw | Mac access |
|---|---|---|---|---|
| mac-02 | UGREEN, installed 2026-08-14 | `429722566` | `eecs2435` | Screen Sharing.app (Remote Management on) |
| mac-03/05/06 | not yet | — | — | add a plug + repeat this runbook |

## CLI reference (for diagnosis only — the *enable* is still a GUI toggle)

```sh
KS=/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart
# fully purge a stuck Remote-Management state that causes "not permitted":
sudo "$KS" -deactivate -stop
sudo rm -f /private/etc/RemoteManagement.launchd /Library/Preferences/com.apple.RemoteManagement.plist
# then re-enable Screen Sharing (or Remote Management) in System Settings GUI.
```
