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
| 20 | `20-ft232-venv.sh` | `~/venvs/ft232` — `pyftdi numpy jupyter` (direct, not conda) |
| 30 | `30-rtk-venv.sh` | `~/venvs/rtk` — `pyserial` (direct, not conda) |
| 40 | `40-ssh-remote.sh` | **SSH** (Remote Login) + **Screen Sharing** (VNC) |

### Environment design (per Yi's instructions)
- **One Miniconda env** (`usrp`) for **all USRP + GNU Radio/GRC** work — and it
  also carries the **LRLocal-V2 Python branch** (`03-tag-template-gen-code`)
  deps (jupyter/pandas/tqdm), so there's no separate env for that.
- **FT232 and RTK are installed directly** in their own venvs, not in conda.
- **UHD pinned to 4.9.x** in the env to match the version the USRP host apps
  were verified against (radioconda UHD 4.9.0.0 in the run-steps). The installer
  auto-falls-back to unpinned UHD if conda-forge can't solve the pin here.

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
| **FT232_SCAN_IO** | `source ~/venvs/ft232/bin/activate`, plug in the FT232H, `jupyter notebook` the project's `Test.ipynb`. Verify the board: `python3 -c "from pyftdi.ftdi import Ftdi; Ftdi.show_devices()"`. |
| **RTK_dev_for_cm-loc** | `source ~/venvs/rtk/bin/activate`, then `python3 relposned_monitor.py --mode web --port /dev/cu.usbmodemXXXXXX`. |

## Manual prerequisites (licensed — NOT scripted)

These can't be automated (licensing / size / non-redistributable) — install by hand:

- **MATLAB R2018b+** with **Signal Processing** + **Parallel Computing** toolboxes
  — required for LRLocal-V2's `01-`/`02-` MATLAB analysis & detection pipeline.
- **Xilinx Vivado** + USRP X310 FPGA/RFNoC toolchain — only if you rebuild FPGA
  bitstreams (USRP `rx-fft*`, `rx-fir-lowpass*`) or simulate the chip RTL
  (FT232 / LRLocal `verilog/`, `vsim/`). Running the host apps does **not** need it.
- **Foundry PDK IP** (TSMC 28 nm SRAM/eFuse/ESD macros) — gitignored and not
  redistributable; the chip RTL won't simulate standalone without it.

## Remote access (step 40)

- **SSH:** `ssh <user>@<ip>` once Remote Login is on. Add collaborators' public
  keys to `~/.ssh/authorized_keys`. The script prints this machine's user / host
  / LAN IP.
- **Screen Sharing (GUI):** connect to `vnc://<ip>` (Finder ▸ Go ▸ Connect to
  Server, or the Screen Sharing app). Needed for GRC, Jupyter, and MATLAB GUIs.
- macOS **privacy (TCC)** may refuse the toggles from a script. If so, grant the
  Terminal app **Full Disk Access** (System Settings ▸ Privacy & Security), or
  flip **Remote Login** / **Screen Sharing** in System Settings ▸ General ▸
  Sharing. Off-LAN access additionally needs router port-forwarding or a VPN.

## Notes
- Apple-Silicon (`arm64`) assumed throughout (Miniconda + libusb downloads).
- Re-running `setup-all.sh` after editing `env/usrp-env.yml` updates the conda
  env in place (`conda env update --prune`).
