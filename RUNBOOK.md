# RUNBOOK — set up a fresh Mac mini from zero

> **Review status:** ⏳ Unreviewed *(default; update when Yi reviews)*
>
> ✍️ *Claude-authored.* Step-by-step to take a brand-new Apple-Silicon Mac mini
> to "can build & run all four project repos + remote access". The numbered
> scripts automate most of it; this runbook is the human walkthrough including
> the bits that **can't** be scripted (MATLAB, sudo toggles, GitHub auth).
>
> Parts of this were executed and verified on a real Mac mini on **2026-06-03**
> (see the ✅/⚠️ markers per step).

---

## 0. Before you start — what you need

- The Mac mini, signed into a macOS user account with **admin** rights.
- A **GitHub account with access to the `Worshisy` private repos**.
- A **MathWorks account + MATLAB license** (for LRLocal-V2's MATLAB code).
- Network access.

Four target repos:
| Repo | Needs |
|---|---|
| `FT232_SCAN_IO` | `usrp` conda env (pyftdi + libusb) |
| `LRLocal-V2` | MATLAB + toolboxes, **and** a Python branch (`usrp` conda env) |
| `USRP_study_yishen` | `usrp` conda env (UHD 4.9 + GNU Radio/GRC + build tools) |
| `RTK_dev_for_cm-loc` | `usrp` conda env (pyserial) |

> **One environment:** a single Miniconda env (`usrp`) covers all of these —
> `conda activate usrp` and everything's available. No per-tool venvs.

---

## 1. Xcode Command Line Tools ✅ verified

```sh
xcode-select --install     # GUI installer; skip if `xcode-select -p` already prints a path
```
Gives you `git`, `clang`, `make`. (Was already present on the test Mac mini.)

---

## 2. Get this setup repo

```sh
git clone https://github.com/Worshisy/LRLocal-Mac-EnvSetup.git
cd LRLocal-Mac-EnvSetup
chmod +x *.sh
```

---

## 3. Authenticate to GitHub (for the private repos) ✅ verified

Install GitHub CLI and log in (no Homebrew needed — direct binary):

```sh
# Apple-Silicon gh binary into ~/.local/bin
VER=$(curl -s https://api.github.com/repos/cli/cli/releases/latest | sed -nE 's/.*"tag_name": *"v?([^"]+)".*/\1/p' | head -1)
curl -sL -o /tmp/gh.zip "https://github.com/cli/cli/releases/download/v${VER}/gh_${VER}_macOS_arm64.zip"
cd /tmp && unzip -oq gh.zip && mkdir -p ~/.local/bin && cp gh_${VER}_macOS_arm64/bin/gh ~/.local/bin/ && cd -

~/.local/bin/gh auth login      # GitHub.com → HTTPS → login with browser
~/.local/bin/gh auth status     # confirm: "Logged in to github.com"

# IMPORTANT: make plain `git` clone/push private repos over HTTPS — including
# over SSH sessions. Use a FILE-based credential store (no macOS Keychain), so
# it works headless. This is the only approach that works over SSH.
TOKEN=$(~/.local/bin/gh auth token)
printf 'https://Worshisy:%s@github.com\n' "$TOKEN" > ~/.git-credentials
chmod 600 ~/.git-credentials
# Use ONLY the file 'store' helper (the empty value drops macOS's default
# osxkeychain helper, which errors -25308 in an SSH session):
git config --global --unset-all credential.helper 2>/dev/null || true
git config --global --add credential.helper ''
git config --global --add credential.helper store
```

> **Why not the Keychain (`osxkeychain`) or `gh auth setup-git`?** Both read the
> macOS **login Keychain**, which is **locked in an SSH session** (no GUI login
> to unlock it) → `git clone` fails with `failed to get: -25308` and falls back
> to a password prompt. They *appear* to work in a local GUI Terminal but break
> the moment you SSH in. The file store above works in both. *(Hit + fixed on
> the Mac mini 2026-06-03 — the machine is used over SSH.)*
>
> ⚠️ The token sits in **plaintext** at `~/.git-credentials` (mode 600 — only
> your account). If others share this macOS account, they can read it; give
> collaborators **separate accounts**, or use **SSH keys** instead:
> `ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""` then add `~/.ssh/id_ed25519.pub`
> to GitHub (Settings ▸ SSH keys, or `gh auth refresh -s admin:public_key &&
> gh ssh-key add ~/.ssh/id_ed25519.pub`) and clone via `git@github.com:Worshisy/<repo>.git`.

---

## 4. Clone the 4 project repos ✅ verified (script)

`clone-repos.sh` is **self-contained for auth** — it installs `gh` if missing,
runs `gh auth login` (browser or token) if you're not logged in, sets up a git
credential store, then clones. By **default it clones into the parent dir of this
kit** (`../`), so the repos sit as **siblings of `LRLocal-Mac-EnvSetup`** (not a
separate `~/Projects`). Pass a path to override.
```sh
./clone-repos.sh                     # clones all 4 into ../ ; PULLS USRP submodules by default
./clone-repos.sh /some/other/dir     # or a chosen location
WITH_SUBMODULES=0 ./clone-repos.sh   # skip the uhd+gnuradio source (several GB)
```
> USRP's `uhd/` + `gnuradio/` submodule **source is now pulled by default**
> (several GB). The **host apps** (`00-`/`01-`/`11-`/…) actually run off the
> conda UHD and don't need it — set `WITH_SUBMODULES=0` to skip if you only want
> to run, not study/build FPGA bitstreams.
> *(Paths below say `~/Projects/<repo>` as an example — substitute wherever you
> cloned, e.g. the kit's parent dir.)*

> **USRP capture volume:** the USRP RX-to-SSD apps historically run from an
> external SSD (`/Volumes/USRP01/…`). Clone wherever you like; just point each
> project's `run.conf` at the right capture path.

---

## 5. Run the environment setup

```sh
./setup-all.sh            # interactive, pauses before each step
# or per-step:  ./setup-all.sh 00   etc.
```

What each step does and its state on the test machine:

### Step 00 — base tools ⚠️ needs sudo (run interactively) ✅ verified
Xcode CLT check, **Homebrew**, **libusb**. This is the **default first step** —
Homebrew is the system package manager and provides the libusb FT232 prefers.
The Homebrew installer asks for your sudo password once, so run it yourself in a
Terminal (as your normal user — **not** `sudo`):
```sh
./00-base-tools.sh
```
> FT232 (step 20) uses this system libusb when present, and only falls back to a
> pip-bundled `libusb-package` if Homebrew isn't installed — so step 00 is the
> preferred path, with the pip fallback as a safety net.

### Step 10 — Miniconda + the `usrp` conda env ✅ verified (no sudo)
Installs Miniconda, then the single env from `env/usrp-env.yml`: **UHD 4.9**,
**GNU Radio/GRC**, cmake/clang/boost, numpy/scipy/matplotlib, and the
LRLocal-V2 Python branch deps (jupyter/pandas/tqdm).
```sh
./10-usrp-conda-env.sh
conda activate usrp
```
> **Gotcha handled:** fresh Miniconda blocks `conda env create` behind an
> Anaconda Terms-of-Service check on the `pkgs/main` / `pkgs/r` channels even
> though we only use conda-forge. The script accepts those ToS automatically.
>
> **No auto-activate:** the script sets `auto_activate_base false`, so new
> shells do **not** drop you into `base` — activate envs on demand with
> `conda activate usrp`. (To re-enable: `conda config --set auto_activate_base true`.)
>
> **UHD device images:** the script also runs `uhd_images_downloader` (conda's
> `uhd` package doesn't bundle the firmware/FPGA images). Without them
> `uhd_usrp_probe` fails with *"Could not load firmware … No EOF record found"*.
> They land in `$CONDA_PREFIX/share/uhd/images`. Re-run `uhd_images_downloader`
> by hand anytime if a probe complains about a missing image. *(Verified on the
> Mac mini 2026-06-06: after download, B200 firmware loads in `uhd_usrp_probe`.)*

### FT232 / RTK / Saleae — folded into the conda env (no separate venvs)
These used to be standalone venvs (steps 20/30/60). They're now just part of the
single `usrp` conda env (step 10), so there's nothing extra to run:
- **FT232_SCAN_IO** → `pyftdi` + conda `libusb` (verified detecting the FT232H
  `ftdi://ftdi:232h:1/1`).
- **RTK_dev_for_cm-loc** → `pyserial`.
- **Saleae** → `logic2-automation` (drives the Logic 2 desktop app, manual §6).

Just `conda activate usrp` and use them. (The old per-tool venv scripts and
`~/venvs/*` were removed — redundant once the deps live in the conda env.)

### Step 50 — SCAN_sourcemeter — ❌ REMOVED (not viable on Apple Silicon)
The Keithley 2401 SMU sweeps (`SweepPV.ipynb`) drive the instruments over a
**Keysight 82357B USB-GPIB** adapter (`GPIB0/1::24::INSTR`). This **cannot work
on an Apple-Silicon Mac**, verified the hard way on 2026-06-06:
- NI's GPIB kexts (`ni488k`, `nipalk`) are **x86_64-only (no `arm64e`)** → can't
  load on Apple Silicon at all (kexts don't run under Rosetta).
- NI-VISA ≥ 2022 Q4 (the only version that runs on modern macOS) **dropped GPIB**.
- The community `macosx_gpib_lib` (x86_64, under Rosetta) loads but enumerates
  **0 boards** on macOS 26 (raw USB/IOKit blocked).
- NI's own KB confirms: no GPIB on modern macOS / Apple Silicon.

**To use the source meter:** run it on an **Intel Mac** (NI x86_64 kexts load),
or switch the transport to a **Prologix GPIB-USB** or the **2401's RS-232** port
(both are pure serial — work natively on Apple Silicon) and adapt `SweepPV.ipynb`.
The step `50-sourcemeter-venv.sh` was removed from this kit.

### Step 70 — gr-filerepeater OOT module (for GRC flowgraphs)
`USRP_study_yishen/grc/*.grc` (B200_FileRec, B200_SpecAna) use blocks from the
out-of-tree module **gr-filerepeater** (`filerepeater_AdvFileSink`,
`filerepeater_StateOr`, `filerepeater_StateTimer`). Without it, GRC shows
**"Missing Block"**. It's a C++/pybind11 OOT module (GNU Radio 3.9+) and must be
**compiled against the GR 3.10 in the `usrp` env** — not available on
conda-forge/pip.
```sh
./70-gr-filerepeater.sh          # clones ghostop14/gr-filerepeater -> ~/src, builds into $CONDA_PREFIX
```
> Source: <https://github.com/ghostop14/gr-filerepeater>. Builds into the conda
> env so `gnuradio-companion` finds the block defs. Restart `grc` after.
> Only needed if you open those GRC flowgraphs; the headless C++ apps don't use it.

### Step 40 — remote access ⚠️ needs sudo (run interactively) ✅ verified
Enables **SSH (Remote Login)** + **Screen Sharing (VNC)**, prepares
`~/.ssh/authorized_keys`, and prints this Mac's user / IP for collaborators.
Run it as your normal user (it calls sudo itself — **don't** prefix with sudo):
```sh
./40-ssh-remote.sh
```

**Screen Sharing** turns on from the script. **Remote Login (SSH) usually does
NOT** — modern macOS requires the *calling Terminal app to have Full Disk
Access* (a privacy/TCC permission) before `systemsetup -setremotelogin on` is
allowed. You'll see:
`setremotelogin: Turning Remote Login on or off requires Full Disk Access privileges.`

**Enable Remote Login the easy way (no Full Disk Access needed):**
1. **System Settings ▸ General ▸ Sharing**
2. Toggle **Remote Login** → **ON**
3. Click the ⓘ next to it → set "Allow access for" to your user (or All users)

Then re-running `./40-ssh-remote.sh` reports `Remote Login already On`.
*(This is the path verified on the Mac mini 2026-06-03.)*

> ⚠️ **Avoid the Full Disk Access route if a session is running in your
> Terminal.** Granting Terminal FDA only takes effect after you **quit and
> reopen** Terminal — which kills anything running in it (e.g. a Claude Code
> tab). The Sharing toggle above needs no FDA and no restart, so prefer it.

> **Screen Sharing note:** if the `launchctl` path is refused, enable
> **Screen Sharing** in the same *System Settings ▸ General ▸ Sharing* pane.

### Step 80 — Headless field Wi-Fi AP (standalone, no uplink)
Make the mini broadcast its **own Wi-Fi AP at `192.168.2.1`** so a laptop joins
and SSHes in **with no display/keyboard** — for field use. **Full walkthrough +
reboot tests: [docs/field-setup.md](docs/field-setup.md).**
```sh
./80-hotspot.sh        # automates the scriptable parts; walks the GUI parts
```
The script automates: **Wi-Fi cleanup** (so it won't auto-join an SSID at boot),
**never-sleep + auto-restart on power failure**, **disable auto-updates**, and a
**LaunchDaemon that re-kicks the AP ~30 s after cold boot**. You still do by hand
(one-time, with a display): **FileVault OFF** + **auto-login** (headless boot),
and the **Internet Sharing AP** itself —
> **The AP trick:** share *from* **Ethernet** *to* **Wi-Fi**, with a **dummy
> wired uplink** (loopback plug / dead switch / bare USB-Ethernet) — Internet
> Sharing needs *link*, not real internet. Set SSID (`macmini-field`) + WPA2/WPA3
> password in **Wi-Fi Options**, toggle ON. If a campus **802.1X** cable is
> plugged in, unplug it (macOS won't share an 802.1X source). Verify
> `ifconfig | grep -A3 '^bridge'` shows `bridge100 → 192.168.2.1`, then
> `ssh <user>@192.168.2.1` from the laptop. **Run the Phase-3 reboot/power-fail
> tests before the field.**

---

## 6. MATLAB (manual — licensed, NOT scriptable) — for LRLocal-V2

LRLocal-V2's `01-system-analysis-code/` and `02-field-detection-code/` are
MATLAB. Required: **MATLAB R2018b or newer**, with the **Signal Processing
Toolbox** and **Parallel Computing Toolbox** (the CFO sweeps use `parfor`).

1. Sign in at <https://www.mathworks.com> with your licensed account.
2. Download the **macOS (Apple silicon)** installer.
3. Run the installer; sign in; pick the license.
4. On the products screen, select at minimum:
   - MATLAB
   - **Signal Processing Toolbox**
   - **Parallel Computing Toolbox**
5. Finish; launch MATLAB once to confirm activation.
6. (Optional) add MATLAB to PATH for CLI use:
   ```sh
   sudo ln -sf /Applications/MATLAB_R20XXx.app/bin/matlab /usr/local/bin/matlab
   ```
7. In MATLAB, verify toolboxes: `ver` should list Signal Processing + Parallel
   Computing. Then `cd` into `LRLocal-V2/02-field-detection-code` and follow
   that repo's `START.md` / `AGENTS.md`.

---

## 7. Verify each repo

> **One env for everything — `conda activate usrp`.** No per-tool venvs.

```sh
conda activate usrp         # ← do this once; covers all of the below

# USRP / GNU Radio
uhd_find_devices            # lists a connected USRP (or "no devices" if none attached)
gnuradio-companion          # GRC GUI (needs a display / Screen Sharing); or: grc <flowgraph>
python -c "import uhd, gnuradio; print(uhd.__version__)"
cd ~/Projects/USRP_study_yishen/00-rx-to-ssd-b200/apps && mkdir -p build && cd build && cmake .. && make -j

# FT232
python -c "from pyftdi.ftdi import Ftdi; Ftdi.show_devices()"   # expect ftdi://ftdi:232h:.../1

# RTK
ls /dev/cu.usbmodem*        # find the rover port
python ~/Projects/RTK_dev_for_cm-loc/relposned_monitor.py --mode web --port /dev/cu.usbmodemXXXXXX

# LRLocal-V2 Python branch
cd ~/Projects/LRLocal-V2/03-tag-template-gen-code && jupyter notebook
```

> Verified in the `usrp` env: UHD 4.9.0.0, GNU Radio 3.10.12, `pyserial`,
> `pyftdi` detecting the FT232H (`ftdi://ftdi:232h:1/1`) via conda's libusb,
> `saleae.automation`, and the `filerepeater` blocks — all from one env.

---

## 8. Remote access — connecting in

After step 40, collaborators connect with the info the script printed:
- **Terminal:** `ssh <user>@<lan-ip>` (add their public key to
  `~/.ssh/authorized_keys`, or use the account password).
- **GUI:** `vnc://<lan-ip>` (Finder ▸ Go ▸ Connect to Server, or the Screen
  Sharing app) — needed to drive GRC / Jupyter / MATLAB GUIs.
- **Off-LAN** access needs router port-forwarding or a VPN (out of scope).

---

## 8b. Sync files to/from this Mac (rsync over SSH)

Run these on the **other** computer (the source). Substitute this Mac's
`<user>@<ip>` (the step-40 output prints them; e.g. `ddh-macmini4-01@<lan-ip>`).
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

## 9. Troubleshooting quick hits

| Symptom | Fix |
|---|---|
| `CondaToSNonInteractiveError` on env create | `conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main` (and `…/pkgs/r`) — step 10 does this automatically |
| `conda env create` can't solve `uhd=4.9` | step 10 auto-retries unpinned; or edit `env/usrp-env.yml` to `uhd` |
| pyftdi `Access denied` / can't open FT232H | the FTDI **VCP/D2XX** driver grabbed the device — don't install it; use a powered hub; libusb backend only |
| `show_devices()` lists nothing | bad cable/power, or not an FT232H |
| Homebrew install hangs | it needs your sudo password — run `./00-base-tools.sh` in an interactive Terminal |
| Remote Login / Screen Sharing won't enable from script | grant Terminal Full Disk Access, or toggle in System Settings ▸ General ▸ Sharing |
| `cmake` finds Homebrew UHD instead of conda's | `conda activate usrp` BEFORE `cmake` so `CONDA_PREFIX` wins (the CMakeLists prepends it) |

---

## Manual prerequisites recap (not automated)
- **MATLAB** + Signal Processing + Parallel Computing toolboxes (§6).
- **Xilinx Vivado** + USRP X310 FPGA/RFNoC toolchain — only for rebuilding
  bitstreams / simulating RTL (`rx-fft*`, `rx-fir*`, FT232 & LRLocal `verilog/`).
- **Foundry PDK IP** (TSMC 28 nm macros) — gitignored, not redistributable.
- **SCAN_sourcemeter / GPIB** — *not available on Apple Silicon* (see Step 50
  above). The Keysight 82357B has no macOS driver; NI GPIB kexts are x86_64-only
  and NI-VISA dropped GPIB. Run on an Intel Mac, or move to a Prologix GPIB-USB /
  RS-232 (serial) adapter. Removed from this kit.
- **Saleae Logic 2 desktop app** — capture software for the Saleae analyzer
  (the `logic2-automation` pip package in step 60 only drives it). Install from
  <https://www.saleae.com/downloads/>; enable its Automation server to script it.
