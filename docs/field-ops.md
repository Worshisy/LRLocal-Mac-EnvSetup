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
| Kit path on mini | `~/LRLocal-Mac-EnvSetup` |
| RTK dashboard | `http://192.168.2.1:8000` |
| Capture logs on mini | `~/field-logs/{rtk,rx}.log` |

---

## 1. Connect

Join the **`macmini-field`** Wi-Fi on your laptop, then:
```sh
ssh ddh-macmini4-0X@192.168.2.1
```
(First time only: accept the host-key prompt. If it says *"Connection closed"* you
used the wrong username — it's `ddh-macmini4-0X`.)

## 2. Start the field jobs (then you can disconnect)
```sh
~/LRLocal-Mac-EnvSetup/field-jobs.sh start      # RTK monitor + USRP RX→SSD, both in tmux
```
Now **close SSH / shut the laptop** — both jobs keep running on the mini.

Start just one if you want: `field-jobs.sh start rtk`  or  `field-jobs.sh start rx`.

## 3. Reconnect later and watch live output
```sh
ssh ddh-macmini4-0X@192.168.2.1
~/LRLocal-Mac-EnvSetup/field-jobs.sh attach rx   # live view of the RX capture
#   detach (leave it running):  Ctrl-b  then  d
~/LRLocal-Mac-EnvSetup/field-jobs.sh attach rtk  # live view of the RTK monitor
```
Prefer a plain scrolling log instead of the tmux view:
```sh
~/LRLocal-Mac-EnvSetup/field-jobs.sh logs rx     # tail -f ~/field-logs/rx.log  (Ctrl-c to stop tailing)
```

## 4. RTK dashboard in a browser (from the laptop)
With the laptop on `macmini-field`, open:
```
http://192.168.2.1:8000
```

## 5. Status / stop
```sh
~/LRLocal-Mac-EnvSetup/field-jobs.sh status      # what's running + log sizes
~/LRLocal-Mac-EnvSetup/field-jobs.sh stop        # stop both (or: stop rx / stop rtk)
```

## 6. Pull captures back to the laptop (end of day)
Run **on the laptop** (the RX writes to the mini's SSD; adjust the source path):
```sh
rsync -avzP ddh-macmini4-0X@192.168.2.1:/path/to/captures/  ~/field-data/
```
(For bulk IQ, plug in direct Ethernet — the AP is 2.4/5 GHz Wi-Fi and slow.)

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
- **Override autodetect** (multiple serial devices, custom paths):
  `RTK_PORT=/dev/cu.usbmodemXXXX REPO_BASE=/path ~/LRLocal-Mac-EnvSetup/field-jobs.sh start`
- **Jobs survive SSH drop** because they're in tmux — that's the whole point; don't run them in a bare SSH shell.
- **Don't reboot in the field** unless necessary — the AP can come up degraded. The
  mini is set to never-sleep + auto-restart on power loss (see `field-setup.md`).
- **Wrong-username symptom:** `Connection closed by 192.168.2.1 port 22` → use `ddh-macmini4-0X`.
- Full one-time field build (FileVault off, auto-login, AP, reboot tests): see
  [`field-setup.md`](field-setup.md). Operator commands for the jobs: this file.
