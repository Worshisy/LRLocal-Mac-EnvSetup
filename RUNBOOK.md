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
| `FT232_SCAN_IO` | Python venv (pyftdi) + libusb |
| `LRLocal-V2` | MATLAB + toolboxes, **and** a Python branch (conda env) |
| `USRP_study_yishen` | conda env (UHD 4.9 + GNU Radio/GRC + build tools) |
| `RTK_dev_for_cm-loc` | Python venv (pyserial) |

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

# IMPORTANT: make plain `git` clone/push private repos over HTTPS. Store the gh
# token in the macOS Keychain (Apple's osxkeychain helper, the git default on
# macOS). This works in a GUI Terminal and needs no gh at clone time.
TOKEN=$(~/.local/bin/gh auth token)
printf 'protocol=https\nhost=github.com\nusername=Worshisy\npassword=%s\n\n' "$TOKEN" | git credential-osxkeychain store
printf 'protocol=https\nhost=gist.github.com\nusername=Worshisy\npassword=%s\n\n' "$TOKEN" | git credential-osxkeychain store
```
(Alternative: set up an SSH key on the Mac and add it to your GitHub account.)

> **Don't use `gh auth setup-git` here.** It points github.com *only* at the gh
> credential helper, which must read gh's token from the Keychain at clone time —
> and that read is blocked in a GUI Terminal, so `git clone https://…` falls back
> to a username/password prompt and fails (`Password authentication is not
> supported` / Keychain `-25308`). Storing the token in osxkeychain (above)
> avoids that. If you already ran `gh auth setup-git`, undo it with:
> `git config --global --unset-all credential.https://github.com.helper`
> *(Hit + fixed on the Mac mini 2026-06-03.)*

---

## 4. Clone the 4 project repos ✅ verified (script)

```sh
./clone-repos.sh ~/Projects          # clones all 4 into ~/Projects
# Need the UHD/GNU Radio *source* too (study / FPGA builds, several GB)?
WITH_SUBMODULES=1 ./clone-repos.sh ~/Projects
```
> The USRP **host apps** (`00-`/`01-`/`11-`/…) run from the conda UHD — you do
> **not** need the `uhd/`+`gnuradio/` submodule source to run them. Only pull
> submodules to read upstream source or build FPGA bitstreams.

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

### Step 00 — base tools ⚠️ needs sudo (run interactively)
Xcode CLT check, **Homebrew**, **libusb**. The Homebrew installer asks for your
sudo password once, so run it yourself in a Terminal:
```sh
./00-base-tools.sh
```
> **Note:** With the no-sudo path below, FT232 (step 20) no longer *requires*
> Homebrew's libusb — step 20 falls back to a pip-bundled libusb. Step 00 is
> still nice to have (a real package manager) but is now optional for these 4.

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

### Step 20 — FT232 venv ✅ verified (no sudo)
`~/venvs/ft232` with `pyftdi numpy jupyter`; auto-installs a pip `libusb-package`
backend if no system libusb. Verified it **detected the attached FT232H**
(`ftdi://ftdi:232h:1/1`) on the test Mac mini.
```sh
./20-ft232-venv.sh
```

### Step 30 — RTK venv ✅ verified (no sudo)
`~/venvs/rtk` with `pyserial`.
```sh
./30-rtk-venv.sh
```

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

```sh
# USRP — conda env has the SDR stack
conda activate usrp
uhd_find_devices            # lists a connected USRP (or "no devices" if none attached)
gnuradio-companion          # GRC GUI opens (needs a display / Screen Sharing)
python -c "import uhd, gnuradio; print(uhd.__version__)"
# build a host app:
cd ~/Projects/USRP_study_yishen/00-rx-to-ssd-b200/apps && mkdir -p build && cd build && cmake .. && make -j

# FT232
source ~/venvs/ft232/bin/activate
python -c "from pyftdi.ftdi import Ftdi; Ftdi.show_devices()"   # expect ftdi://ftdi:232h:.../1

# RTK
source ~/venvs/rtk/bin/activate
ls /dev/cu.usbmodem*        # find the rover port
python ~/Projects/RTK_dev_for_cm-loc/relposned_monitor.py --mode web --port /dev/cu.usbmodemXXXXXX

# LRLocal-V2 Python branch
conda activate usrp
cd ~/Projects/LRLocal-V2/03-tag-template-gen-code && jupyter notebook
```

---

## 8. Remote access — connecting in

After step 40, collaborators connect with the info the script printed:
- **Terminal:** `ssh <user>@<lan-ip>` (add their public key to
  `~/.ssh/authorized_keys`, or use the account password).
- **GUI:** `vnc://<lan-ip>` (Finder ▸ Go ▸ Connect to Server, or the Screen
  Sharing app) — needed to drive GRC / Jupyter / MATLAB GUIs.
- **Off-LAN** access needs router port-forwarding or a VPN (out of scope).

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
