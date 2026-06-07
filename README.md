# LRLocal-Mac-EnvSetup

> **Review status:** ⏳ Unreviewed *(default; update when Yi reviews)*
>
> ✍️ *Claude-authored.* Scripts to bring a **fresh Apple-Silicon Mac mini** up
> to a state where Yi's four project repos can be built and run, plus enable
> remote access. Derived by reading each repo's README / run-steps on 2026-06-03.

Target: a new Mac mini **the same as the current one** — arm64, macOS 26.x,
Apple git + Xcode CLT, system `python3`, **no** Homebrew / conda yet.

## What it sets up

| Step | Script | Covers |
|---|---|---|
| 00 | `00-base-tools.sh` | Xcode Command Line Tools, **Homebrew**, **libusb** |
| 10 | `10-usrp-conda-env.sh` | **Miniconda** + the single `usrp` conda env (`env/usrp-env.yml`) |
| 20 | `20-ft232-venv.sh` | `~/venvs/ft232` — `pyftdi numpy jupyter` + pip libusb (direct, no sudo) |
| 30 | `30-rtk-venv.sh` | `~/venvs/rtk` — `pyserial` (direct) |
| 60 | `60-saleae-venv.sh` | `~/venvs/saleae` — `logic2-automation` (Saleae Logic; direct) |
| 70 | `70-gr-filerepeater.sh` | builds the **gr-filerepeater** OOT module into the `usrp` env (GRC flowgraph blocks) |
| 40 | `40-ssh-remote.sh` | **SSH** (Remote Login) + **Screen Sharing** (VNC) |

### Environment design
- **One Miniconda env** (`usrp`) can run **all four repos**: USRP + GNU
  Radio/GRC, the **LRLocal-V2 Python branch**, **FT232** (`pyftdi` + conda
  `libusb`), and **RTK** (`pyserial`).
- **FT232 and RTK also have their own direct venvs** (`~/venvs/ft232`,
  `~/venvs/rtk`) — so either route works. FT232's venv prefers the **Homebrew
  libusb** (step 00, the default), falling back to a pip-bundled `libusb-package`
  if Homebrew isn't present; the conda env uses conda's `libusb`.
- **SCAN_sourcemeter** (Keithley 2401 SMU over a Keysight 82357B USB-GPIB) is
  **NOT supported on this Apple-Silicon Mac** and was removed from the flow — the
  82357B has no working macOS driver (NI's GPIB kexts are x86_64-only, and NI-VISA
  dropped GPIB). Use an Intel Mac, or move to a Prologix/RS-232 (serial) path.
  See RUNBOOK "source meter" note.
- **UHD pinned to 4.9.x** in the env to match the version the USRP host apps
  were verified against (run-steps record UHD 4.9.0.0). The installer
  auto-falls-back to unpinned UHD if conda-forge can't solve the pin here.

> **Verified on a fresh Mac mini 2026-06-03:** steps 10/20/30 ran with no sudo;
> the `usrp` env resolved **UHD 4.9.0.0 + GNU Radio 3.10.12 + gr-uhd**, a USRP
> C++ host app (`rx_to_ssd_b200`) built & ran, and the attached **FT232H was
> detected** via the pip libusb backend. Steps 00 (Homebrew) and 40 (remote
> access) need sudo — run those interactively. **See [RUNBOOK.md](RUNBOOK.md)
> for the full step-by-step (incl. MATLAB install + cloning the 4 repos).**

## Run it

```sh
git clone https://github.com/Worshisy/LRLocal-Mac-EnvSetup.git
cd LRLocal-Mac-EnvSetup
chmod +x *.sh
./setup-all.sh            # interactive: pauses before each step
# or:  ./setup-all.sh -y  # run everything unattended
# or:  ./setup-all.sh 00 10   # just specific steps
```

Steps are **idempotent** — re-run any one if it fails. Step 00 asks for your
sudo password once (Homebrew); step 40 uses sudo for the remote-access toggles.

## Per-repo: what to do after setup

| Repo | Run it with |
|---|---|
| **USRP_study_yishen** | `conda activate usrp`, then build each `NN-…/apps` (`cmake .. && make`) or run the Python tools — see each project's `notes/run-steps-sy.md`. `git submodule update --init --recursive` only if you need the UHD/GNU Radio **source** (several GB; for study/FPGA, not for running the host apps). |
| **LRLocal-V2** | MATLAB side needs **MATLAB** (manual, below). Python branch: `conda activate usrp`, then `jupyter notebook` inside `03-tag-template-gen-code/`. |
| **FT232_SCAN_IO** | `source ~/venvs/ft232/bin/activate` **or** `conda activate usrp`, plug in the FT232H, `jupyter notebook` the project's `Test.ipynb`. Verify the board: `python3 -c "from pyftdi.ftdi import Ftdi; Ftdi.show_devices()"`. |
| **RTK_dev_for_cm-loc** | `source ~/venvs/rtk/bin/activate` **or** `conda activate usrp`, then `python3 relposned_monitor.py --mode web --port /dev/cu.usbmodemXXXXXX`. |
| **Saleae Logic** (tool) | `source ~/venvs/saleae/bin/activate` **or** `conda activate usrp` for the `logic2-automation` Python API. Capture itself runs in the **Logic 2 desktop app** (manual install, below). |
| ~~SCAN_sourcemeter~~ | **Removed** — Keithley 2401 via Keysight 82357B GPIB has no Apple-Silicon driver. Needs an Intel Mac or a Prologix/RS-232 path. |

## Manual prerequisites (licensed — NOT scripted)

These can't be automated (licensing / size / non-redistributable) — install by hand:

- **MATLAB R2018b+** with **Signal Processing** + **Parallel Computing** toolboxes
  — required for LRLocal-V2's `01-`/`02-` MATLAB analysis & detection pipeline.
- **Xilinx Vivado** + USRP X310 FPGA/RFNoC toolchain — only if you rebuild FPGA
  bitstreams (USRP `rx-fft*`, `rx-fir-lowpass*`) or simulate the chip RTL
  (FT232 / LRLocal `verilog/`, `vsim/`). Running the host apps does **not** need it.
- **Foundry PDK IP** (TSMC 28 nm SRAM/eFuse/ESD macros) — gitignored and not
  redistributable; the chip RTL won't simulate standalone without it.
- ~~**NI-VISA / GPIB** for SCAN_sourcemeter~~ — **not viable on Apple Silicon**
  (NI's GPIB kexts are x86_64-only; NI-VISA ≥2022Q4 dropped GPIB; the Keysight
  82357B has no macOS driver). The source meter is removed from this flow; run it
  on an Intel Mac, or switch to a Prologix GPIB-USB / RS-232 (serial) adapter.
- **Saleae Logic 2 desktop app** — the capture software for the Saleae logic
  analyzer (the `logic2-automation` pip package in step 60 only *drives* it).
  Install from <https://www.saleae.com/downloads/>; enable the Automation server
  in its Preferences to use the Python API.

## Remote access (step 40)

Run `./40-ssh-remote.sh` **as your normal user** (it calls sudo itself).
**Screen Sharing** enables from the script; **Remote Login (SSH) usually needs
one manual GUI step** (see below).

- **Enable Remote Login (SSH) — easy way, no Full Disk Access needed:**
  modern macOS refuses `systemsetup -setremotelogin on` from a script
  (`...requires Full Disk Access privileges`). Instead:
  1. **System Settings ▸ General ▸ Sharing**
  2. Toggle **Remote Login** → **ON**
  3. ⓘ next to it → "Allow access for" your user (or All users)

  Re-running the script then shows `Remote Login already On`. *(Verified on the
  Mac mini 2026-06-03.)*
  > ⚠️ Don't grant **Terminal** Full Disk Access to force it — that only takes
  > effect after you quit & reopen Terminal, which kills anything running in it
  > (e.g. a Claude Code tab). The Sharing toggle needs neither FDA nor a restart.
- **SSH in:** `ssh <user>@<ip>`. Add collaborators' public keys to
  `~/.ssh/authorized_keys` (one per line). The script prints user / host / LAN IP.
- **Screen Sharing (GUI):** connect to `vnc://<ip>` (Finder ▸ Go ▸ Connect to
  Server, or the Screen Sharing app). Needed for GRC, Jupyter, MATLAB GUIs.
  If the script's `launchctl` path is refused, enable **Screen Sharing** in the
  same *System Settings ▸ General ▸ Sharing* pane.
- **Off-LAN** access additionally needs router port-forwarding or a VPN.

## Notes
- Apple-Silicon (`arm64`) assumed throughout (Miniconda + libusb downloads).
- Re-running `setup-all.sh` after editing `env/usrp-env.yml` updates the conda
  env in place (`conda env update --prune`).
