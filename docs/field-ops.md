# Field Ops — drive the Mac mini from your laptop (host) over SSH

> **Review status:** ⏳ Unreviewed *(default; update when Yi reviews)*
>
> ✍️ *Claude-authored.* Operator cheat-sheet: run everything **from the host
> (your laptop)**; the jobs run **on the slave (the field Mac mini)** where the
> B200 + RTK rover are attached. Jobs run in tmux, so they survive you closing
> SSH and you can re-attach to see live output.

## Coordinates

> **Fleet of up to 6 minis.** Each unit's login user is **`ddh-macmini4-0X`**
> where **`X` = that mini's number (01–06)** — e.g. `ddh-macmini4-02`. Substitute
> your unit's number in every command below. Give each mini its **own AP SSID**
> too (e.g. `macmini-field-0X`) so two units never collide on the air; the AP IP
> is `192.168.2.1` on each (you're only ever joined to one at a time).

| | |
|---|---|
| Field AP (Wi-Fi) | SSID **`macmini-field-0X`** · pw **`eecs2435`** · ch 40 (5 GHz, 2.4 fallback) |
| Mac mini IP | **`192.168.2.1`** (on whichever unit's AP you're joined to) |
| SSH user | **`ddh-macmini4-0X`** (X = unit #, 01–06) |
| SSH shortcut | **`ssh ddh-mac-0X`** — after running `host-000-ssh-config.sh` once on your laptop |
| Kit path on mini | `~/LRLocal-Mac-EnvSetup` |
| TX Pi AP | SSID **`ddh-pi4-beacon`** · pw **`eecs2435`** · Pi = **`192.168.3.1`** · `ssh ddh-pi4-beacon` (user `user`) |
| RTK dashboard | `http://192.168.2.1:8000` |
| Capture logs on mini | `~/field-logs/{rtk,rx}.log` |

---

## 1. Connect

One-time on your laptop: run the kit's `host-000-ssh-config.sh` — it installs
`ssh ddh-mac-0X` shortcuts (user + IP + the reverse-SOCKS forward + host-key
quieting) into your `~/.ssh/config`.

Join the **`macmini-field-0X`** Wi-Fi on your laptop, then:
```sh
ssh ddh-mac-0X                      # short form (after host-000-ssh-config.sh)
ssh ddh-macmini4-0X@192.168.2.1     # long form, works anywhere
```
(If it says *"Connection closed"* you used the wrong username — it's
`ddh-macmini4-0X`.)

## 2. Start the field jobs (then you can disconnect)
```sh
~/LRLocal-Mac-EnvSetup/field-000-jobs.sh start      # RTK monitor + USRP RX→SSD, both in tmux
```
Starting **rx** prompts for the **RX center frequency in GHz** (e.g. `2.55`;
Enter = run.conf default), then an optional **start time** (`HH:MM` local for a
deferred start; Enter = start now; a past time runs tomorrow).
Now **close SSH / shut the laptop** — both jobs keep running on the mini.

Start just one if you want: `field-000-jobs.sh start rtk`  or  `field-000-jobs.sh start rx`.

## 3. Reconnect later and watch live output
```sh
ssh ddh-macmini4-0X@192.168.2.1
~/LRLocal-Mac-EnvSetup/field-000-jobs.sh attach rx   # live view of the RX capture
#   detach (leave it running):  Ctrl-b  then  d
~/LRLocal-Mac-EnvSetup/field-000-jobs.sh attach rtk  # live view of the RTK monitor
```
Prefer a plain scrolling log instead of the tmux view:
```sh
~/LRLocal-Mac-EnvSetup/field-000-jobs.sh logs rx     # tail -f ~/field-logs/rx.log  (Ctrl-c to stop tailing)
```

## 4. RTK dashboard in a browser (from the laptop)
With the laptop on `macmini-field`, open:
```
http://192.168.2.1:8000
```

## 5. Status / stop
```sh
~/LRLocal-Mac-EnvSetup/field-000-jobs.sh status      # what's running + log sizes
~/LRLocal-Mac-EnvSetup/field-000-jobs.sh stop        # stop both (or: stop rx / stop rtk)
```

## 6. Pull captures back to the laptop (end of day)
Run **on the laptop**. The mini has a stable symlink **`rx-data` → the RX
capture dir** next to the kit (in `~` when the kit is at `~/LRLocal-Mac-EnvSetup`):
```sh
rsync -avzP ddh-mac-0X:rx-data/  ~/field-data/
```
(For bulk IQ, plug in direct Ethernet — the AP is 2.4/5 GHz Wi-Fi and slow.)

Capture SSD full (rx job dead, git pulls failing with "No space left")? After
offloading, wipe the captures on the mini — takes **3 typed confirmations**:
```sh
~/LRLocal-Mac-EnvSetup/field-020-empty-rx-data.sh
```

## 6b. Give the mini internet through your laptop (git pull, installs)

The mini's AP has no uplink, but every `ssh ddh-mac-0X` carries a **reverse
SOCKS proxy** (`RemoteForward 1080`): traffic the mini sends to
`localhost:1080` exits via **your laptop's** internet. On the mini:

```sh
gitp -C ~/LRLocal-Mac-EnvSetup pull   # gitp = git through the proxy (alias from step 040)
proxyon                               # or: proxy everything in this shell (curl/brew/pip…)
proxyoff
~/LRLocal-Mac-EnvSetup/field-010-update-repos.sh   # or: update ALL repos + the kit in one go (ff-only)
```

Connected without the shortcut? `ssh -R 1080 ddh-macmini4-0X@192.168.2.1`
gives the same tunnel. pip/conda additionally need `pysocks` to speak SOCKS.

## 7. GUI when you need it (VNC)
```sh
open vnc://192.168.2.1            # log in as ddh-macmini4-0X
```
If it says *"Screen Sharing is not permitted"*, fix over SSH:
```sh
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -deactivate -stop
sudo launchctl bootout   system /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null
sudo launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.screensharing.plist
```

---

## Notes & gotchas
- **One env runs everything:** the jobs `conda activate usrp` themselves — you don't need to.
- **Override autodetect** (multiple serial devices, custom paths, skip the freq prompt):
  `RTK_PORT=/dev/cu.usbmodemXXXX REPO_BASE=/path RX_FREQ=2.55 ~/LRLocal-Mac-EnvSetup/field-000-jobs.sh start`
- **Jobs survive SSH drop** because they're in tmux — that's the whole point; don't run them in a bare SSH shell.
- **Don't reboot in the field** unless necessary — the AP can come up degraded. The
  mini is set to never-sleep + auto-restart on power loss (see `field-setup.md`).
- **Wrong-username symptom:** `Connection closed by 192.168.2.1 port 22` → use `ddh-macmini4-0X`.
- **"REMOTE HOST IDENTIFICATION HAS CHANGED" / host key warning:** expected in the
  fleet — every mini reuses `192.168.2.1` but has its own SSH host key.
  `host-000-ssh-config.sh` already quiets this (Macs). One-off fix, or on Windows:
  clear the stale entry with `ssh-keygen -R 192.168.2.1`, or add to
  `C:\Users\<you>\.ssh\config`:
  ```
  Host 192.168.2.1
      StrictHostKeyChecking no
      UserKnownHostsFile NUL            # macOS/Linux: /dev/null
  ```
- Full one-time field build (FileVault off, auto-login, AP, reboot tests): see
  [`field-setup.md`](field-setup.md). Long-form operating reference (rsync,
  shortcuts, offline-mini internet): [`../FIELD-RUNBOOK.md`](../FIELD-RUNBOOK.md).
  Operator commands for the jobs: this file.
