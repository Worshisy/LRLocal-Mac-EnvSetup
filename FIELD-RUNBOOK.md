# FIELD RUNBOOK — operate an already-set-up Mac mini remotely / in the field

> **Review status:** ✅ Fully confirmed *(Yi, 2026-07-28)*
>
> ✍️ *Claude-authored.* Split out of the original `RUNBOOK.md` (2026-07-28):
> everything about **connecting to and operating** a mini that's already been
> built — remote access, file sync, detached field jobs, SSH shortcuts +
> internet for an offline mini. Related docs:
> - **[SETUP-RUNBOOK.md](SETUP-RUNBOOK.md)** — build the machine from zero (steps 010–060).
> - **[docs/field-setup.md](docs/field-setup.md)** — one-time headless field-AP build + reboot tests.
> - **[docs/field-ops.md](docs/field-ops.md)** — operator cheat-sheet (the short version of this file).

---

## 1. Remote access — connecting in

After step 040, collaborators connect with the info the script printed:
- **Terminal:** `ssh <user>@<lan-ip>` (add their public key to
  `~/.ssh/authorized_keys`, or use the account password).
- **GUI:** `vnc://<lan-ip>` (Finder ▸ Go ▸ Connect to Server, or the Screen
  Sharing app) — needed to drive GRC / Jupyter / MATLAB GUIs.
- **Off-LAN** access needs router port-forwarding or a VPN (out of scope).

---

## 2. Sync files to/from this Mac (rsync over SSH)

Run these on the **other** computer (the source). Substitute this Mac's
`<user>@<ip>` (the step-040 output prints them; e.g. `ddh-macmini4-01@<lan-ip>`).
`~/dest` expands to `/Users/<user>/dest` on the Mac.

```sh
# Push a folder UP to this Mac (trailing slash on src = copy its CONTENTS)
rsync -avz -e ssh  ~/local/folder/   <user>@<ip>:~/dest/

# Big files / show progress / resume if interrupted
rsync -avzP -e ssh  bigfile.dat      <user>@<ip>:~/Captures/

# Dry run first — show what WOULD change, copy nothing
rsync -avzn -e ssh  src/             <user>@<ip>:~/dest/

# Skip junk
rsync -avz --exclude '.git' --exclude '.DS_Store' --exclude 'build/' src/  <user>@<ip>:~/dest/

# Mirror exactly (deletes extra files on the Mac — careful)
rsync -avz --delete -e ssh  src/     <user>@<ip>:~/dest/

# Pull FROM this Mac (reverse direction)
rsync -avz -e ssh  <user>@<ip>:~/Projects/USRP_study_yishen/  ./USRP_local/
```

Flags: `-a` archive (recursive + perms/times/symlinks) · `-v` verbose ·
`-z` compress · `-P` progress+resume · `-n` dry-run · `-e ssh` transport.

> **Trailing slash matters:** `rsync src/ dest/` copies the *contents* of `src`
> into `dest`; `rsync src dest/` creates `dest/src/`.
>
> **Auth:** prompts for the account password unless the source machine's SSH
> public key is in this Mac's `~/.ssh/authorized_keys` (then it's passwordless).
>
> **rsync flavor:** this Mac ships Apple's **openrsync** (protocol 29) — the
> flags above all work. For GNU-only extras (`--info=progress2`) install GNU
> rsync with `brew install rsync`.

---

## 3. Long field jobs that survive SSH disconnect (`field-000-jobs.sh`)

Run the RTK monitor + the USRP RX-to-SSD capture so they **keep running after you
close SSH**, and you can **re-attach to see live output**. Uses **tmux**.

**Where:** **on the slave** (the field Mac mini) — the B200 and RTK rover are
physically attached there. Your laptop just SSHes in. The two jobs are:
- `rtk` — `RTK_dev_for_cm-loc` RELPOSNED web monitor (headless, `--host 0.0.0.0`)
- `rx`  — `USRP_study_yishen/01-rx-to-ssd-b200-agc/run.sh` (continuous RX → SSD, AGC)

```sh
ssh ddh-macmini4-0X@192.168.2.1            # into the slave (X = the mini's number, 01–06)
~/LRLocal-Mac-EnvSetup/field-000-jobs.sh start # launches both in tmux, logs to ~/field-logs/
#   …now you can just close the SSH session; both keep running.

# later, reconnect and watch:
~/LRLocal-Mac-EnvSetup/field-000-jobs.sh attach rx   # live tmux view; Ctrl-b then d to detach
~/LRLocal-Mac-EnvSetup/field-000-jobs.sh logs   rtk  # or tail the log file
~/LRLocal-Mac-EnvSetup/field-000-jobs.sh status      # what's running
~/LRLocal-Mac-EnvSetup/field-000-jobs.sh stop        # stop both
```
- RTK web dashboard is reachable from the laptop at **`http://192.168.2.1:8000`**.
- Auto-detects repo locations (kit's parent dir / `~/Projects` / `~`) and the RTK
  serial port. Override: `REPO_BASE=…  RTK_PORT=/dev/cu.usbmodemXXXX  RX_WEBPORT=8000`.
- Starting **rx** always asks for the **RX center frequency in GHz** — type
  `2.55` for 2.55 GHz (Hz forms like `915e6` also accepted; checked against the
  B200 70 MHz–6 GHz range; Enter = keep the run.conf `FREQ`, shown in the
  prompt) — then an optional **start time** —
  Enter = start now, or `HH:MM` local for a deferred start (`run.sh --start`;
  a time already past today schedules for tomorrow, confirmed at the prompt).
  The prompt shows the machine's current time.
  Pre-answer with `RX_FREQ=2.55 RX_START=18:30 … field-000-jobs.sh start`
  (`RX_START=now` skips the prompt; `RX_START_TZ=utc` for UTC times).
- Every `start` also **checks the mini's clock through the operator tunnel**
  (HTTPS Date header — no NTP off-grid) and syncs it via sudo when it's ≥ 2 s
  off, so deferred starts fire at the right wall-clock time. Tunnel down →
  warns and continues with the clock unchecked.
- Each job also tees to `~/field-logs/{rtk,rx}.log`, so output persists even if you
  never attach. `run.sh` respects the already-active `usrp` conda env (won't switch
  to base). Needs `tmux` (in the `usrp` env via step 020, or `conda install -n usrp tmux`).
- Before starting **rx**, it **disables Spotlight on the capture SSD** (`/Volumes/USRP*`,
  or `$CAPTURE_VOL`) — macOS can re-enable it after a reboot, and it would otherwise
  make `run.sh` stop to ask / cause overflows. Uses sudo (you run `start` interactively).

> **Host operator cheat-sheet** (what to type from your laptop over SSH —
> connect, start, detach, re-attach, dashboard, pull captures, VNC):
> [`docs/field-ops.md`](docs/field-ops.md).

---

## 4. SSH shortcuts + internet for an offline field mini (`host-000-ssh-config.sh`)

One-time **on the operator machine** (your laptop / lab Mac — not the mini):
```sh
./host-000-ssh-config.sh      # installs ssh shortcuts ddh-mac-01 … ddh-mac-06
```
After that, `ssh ddh-mac-0X` = `ddh-macmini4-0X@192.168.2.1` and every
connection carries `RemoteForward 1080` — a **reverse SOCKS proxy** so the
otherwise-offline mini can reach the internet **through the operator's
machine**. On the mini (helpers installed by step 040 into `~/.zshrc`):
```sh
gitp pull        # git through the proxy (per-invocation; nothing persists)
proxyon          # proxy this whole shell: curl / brew / git … (proxyoff to undo)
```
It also quiets the fleet host-key warning for `192.168.2.1`. The block is
idempotent (managed markers in `~/.ssh/config`); the rest of your config is
untouched. Without the shortcut, `ssh -R 1080 ddh-macmini4-0X@192.168.2.1`
opens the same tunnel. pip/conda need `pysocks` installed to use a SOCKS proxy.

To update **everything at once** (LRLocal-V2 + USRP + RTK repos + this kit, all
ff-only through the tunnel; FT232_SCAN_IO deliberately excluded):
```sh
~/LRLocal-Mac-EnvSetup/field-010-update-repos.sh
```
Repos with local commits/changes are never merged — they're reported for you
to resolve. `WITH_SUBMODULES=1` also updates USRP's uhd+gnuradio source (GBs).

## 4b. TX Raspberry Pi in the field (`pi-000-hotspot.sh`)

The beacon TX runs on a Raspberry Pi (via `USRP_study_yishen/`
`11-tx-beacon-usrpb200-code`). To reach it headless in the field it broadcasts
its own AP, like the minis but on its **own subnet**:

| | |
|---|---|
| AP | SSID **`ddh-pi4-beacon`** · pw `eecs2435` · ch 40 (auto-falls back to 2.4 GHz) |
| Pi address | **`192.168.3.1`** (`.3.1`, not the minis' `.2.1`) |
| Login | `ssh ddh-pi4-beacon` (= `user@192.168.3.1`; shortcut from `host-000-ssh-config.sh`) |

One-time setup (at home, Pi on Ethernet so you don't cut your own session):
```sh
scp pi-000-hotspot.sh user@<pi-lan-ip>:          # from the laptop / this Mac
ssh user@<pi-lan-ip> ./pi-000-hotspot.sh         # enables sshd + the AP; reboot-safe
```
It configures **only `wlan0` + sshd** (NetworkManager AP, `ipv4.method shared`)
— the USRP TX code, its environment, and eth0 are untouched. Re-run anytime;
`AP_BAND=bg AP_CHAN=6` forces 2.4 GHz; `sudo nmcli con delete pi-field-ap`
removes it. The `ssh ddh-pi4-beacon` shortcut carries the same reverse SOCKS
tunnel, so the offline Pi can still pull. Its clones use the **SSH remote**
(`git@github.com`), which needs the ProxyCommand form (not `http.proxy`):
```sh
GIT_SSH_COMMAND='ssh -o ProxyCommand="nc -X 5 -x 127.0.0.1:1080 %h %p"' \
  git -C ~/USRP_study_yishen pull --ff-only
```
(HTTPS-remote clones would use `git -c http.proxy=socks5h://127.0.0.1:1080 pull`.)

`pi-000-hotspot.sh` also installs **field shortcuts** into the Pi's `~/.bashrc`
(the menu prints at every login; `shortcuts` reprints it):

| | |
|---|---|
| `gitpull` | pull the newest `USRP_study_yishen` — offline OK, rides the tunnel |
| `txfreq` | show the TX center frequency (11-tx `run.conf`) |
| `txfreq 2.55` | set 2.55 GHz (GHz default, ≥1e6 = Hz, B200-range-checked) **and restart the tx-beacon service so it's live immediately** (asks sudo) |
| `txstatus` | TX beacon service status (`deploy/tx-status.sh`) |
| `tx_restart` | restart the TX beacon service (re-reads `run.conf`) |
| `pi_restart` | reboot the whole Pi — AP + TX auto-return in ~1 min |

The TX service (`tx-beacon-b200mini`, system unit) re-reads `run.conf` at every
boot — verified 2026-07-31: a bare `FREQ` edit + reboot came up transmitting at
the new frequency (`act_freq_hz = 2.55e+09` in the run meta).

## 5. Empty the RX capture data (3 typed confirmations)

When the capture SSD fills up (a full disk kills the rx job AND git pulls):
```sh
~/LRLocal-Mac-EnvSetup/field-020-empty-rx-data.sh
```
It resolves the RX data dir (`RX_DATA_DIR`/`run.conf OUT`/`USRP_study_yishen/data`,
also reachable via the `<kit-parent>/rx-data` symlink), refuses while the rx job
is running, lists every item with sizes, then requires **three typed answers**
(`yes` → the item count → `DELETE`) before removing the contents. Offload
anything you want to keep first (§2 rsync / [field-ops §6](docs/field-ops.md)).

