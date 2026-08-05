# LRLocal-Mac-EnvSetup

> **Review status:** ⏳ Unreviewed *(default; update when Yi reviews)*
>
> ✍️ *Claude-authored.* Scripts to bring a **fresh Apple-Silicon Mac mini** up
> to a state where Yi's project repos can be built and run, plus enable
> remote access. Derived by reading each repo's README / run-steps on 2026-06-03.

Target: a new Mac mini **the same as the current one** — arm64, macOS 26.x,
Apple git + Xcode CLT, system `python3`, **no** Homebrew / conda yet.

## What it sets up

> **Script naming:** `<setup|field|host|pi>-XXX-<name>.sh`, where `XXX = 0<step><sub>`
> — sub digit `0` = the step's main script, `1–9` = sub-functions of that step.
> `setup-*` runs once on a fresh mini, `field-*` is used day-to-day on the mini,
> `host-*` runs on the operator laptop, `pi-*` runs on the TX Raspberry Pi.
> *(Renamed 2026-07-28 from the old `00-`/`10-`/`40-`/`70-`/`80-` numbering.)*

| Step | Script | Covers |
|---|---|---|
| 000 | `setup-000-all.sh` | orchestrator — runs steps 010→060 in order |
| 010 | `setup-010-base-tools.sh` | Xcode Command Line Tools (+ optional Homebrew/libusb — conda has its own) |
| 020 | `setup-020-usrp-conda-env.sh` | **Miniconda** + the single `usrp` conda env — **all tools** (`env/usrp-env.yml`) |
| 030 | `setup-030-clone-repos.sh` | clone the 4 project repos (+ `rx-data` symlink + seeds the workspace `../AGENTS.md`); asks GitHub auth if not yet logged in |
| 040 | `setup-040-ssh-remote.sh` | **SSH** (Remote Login) + **Screen Sharing** (VNC) + reverse-SOCKS proxy helpers |
| 050 | `setup-050-gr-filerepeater.sh` | builds the **gr-filerepeater** OOT module into the `usrp` env (GRC flowgraph blocks) |
| 060 | `setup-060-hotspot.sh` | **Headless field Wi-Fi AP** — standalone AP @ `192.168.2.1` for SSH in the field ([docs/field-setup.md](docs/field-setup.md)) |

Day-to-day scripts (see [FIELD-RUNBOOK.md](FIELD-RUNBOOK.md)):

| Script | Runs on | Covers |
|---|---|---|
| `field-000-jobs.sh` | mini | RTK monitor + USRP RX→SSD + PSD viewer + file browser in detached tmux |
| `field-001-psd-web.py` | mini | newest-PSD browser view on :8081 (job `psd` of field-000) |
| `field-020-empty-rx-data.sh` | mini | wipe RX captures — pick records to keep (Enter = newest), one confirm |
| `field-010-update-repos.sh` | mini | git pull LRLocal-V2 + USRP + RTK repos + this kit through the operator tunnel (FT232 excluded) |
| `host-000-ssh-config.sh` | laptop (macOS / Git Bash) | `ssh ddh-mac-0X` / `ssh ddh-pi4-beacon` shortcuts + reverse SOCKS forward + host-key quieting |
| `host-001-ssh-config-windows.ps1` | laptop (Windows) | runs host-000, then the Windows-only fixes: config ACLs, an `ssh -F` profile wrapper, verification |
| `pi-000-hotspot.sh` | TX Raspberry Pi | field Wi-Fi AP `ddh-pi4-beacon` @ `192.168.3.1` + SSH — doesn't touch the USRP TX setup |

### Environment design — ONE conda env for everything
- **A single Miniconda env (`usrp`) runs all the tools** — no per-tool venvs.
  It carries: USRP + GNU Radio/GRC (UHD 4.9), the **LRLocal-V2 Python branch**
  (numpy/scipy/matplotlib/jupyter/pandas/tqdm), **FT232** (`pyftdi` + conda
  `libusb`), **RTK** (`pyserial`), **Saleae** (`logic2-automation`), and the
  **gr-filerepeater** OOT blocks (step 050).
- **Just `conda activate usrp` for everything.** (Earlier per-tool venvs under
  `~/venvs/*` were dropped — redundant once the deps live in the conda env.)
- Homebrew/libusb (step 010) is now **optional** — the conda env brings its own
  `libusb`; Homebrew is only a convenience for other system tooling.
- **SCAN_sourcemeter** (Keithley 2401 SMU over a Keysight 82357B USB-GPIB) is
  **NOT supported on this Apple-Silicon Mac** and was removed from the flow — the
  82357B has no working macOS driver (NI's GPIB kexts are x86_64-only, and NI-VISA
  dropped GPIB). Use an Intel Mac, or move to a Prologix/RS-232 (serial) path.
  See SETUP-RUNBOOK "source meter" note.
- **UHD pinned to 4.9.x** in the env to match the version the USRP host apps
  were verified against (run-steps record UHD 4.9.0.0). The installer
  auto-falls-back to unpinned UHD if conda-forge can't solve the pin here.

> **Verified on a fresh Mac mini 2026-06-03** *(under the pre-rename step
> numbers)*: the conda-env step ran with no sudo; the `usrp` env resolved
> **UHD 4.9.0.0 + GNU Radio 3.10.12 + gr-uhd**, a USRP C++ host app
> (`rx_to_ssd_b200`) built & ran, and the attached **FT232H was detected** via
> the pip libusb backend. Steps 010 (Homebrew) and 040 (remote access) need
> sudo — run those interactively. **See
> [SETUP-RUNBOOK.md](SETUP-RUNBOOK.md) for the full step-by-step (incl. MATLAB
> install + cloning the 4 repos), and [FIELD-RUNBOOK.md](FIELD-RUNBOOK.md) for
> operating a set-up mini remotely / in the field.**

## Run it

```sh
git clone https://github.com/Worshisy/LRLocal-Mac-EnvSetup.git
cd LRLocal-Mac-EnvSetup
chmod +x *.sh
./setup-000-all.sh            # interactive: pauses before each step
# or:  ./setup-000-all.sh -y  # run everything unattended
# or:  ./setup-000-all.sh 010 020   # just specific steps
```

Steps are **idempotent** — re-run any one if it fails. Step 040 uses sudo for the
remote-access toggles (run it as your normal user; it calls sudo itself).

## Per-repo: what to do after setup

**Everything runs in one env — `conda activate usrp` first**, then:

| Repo | Run it with (after `conda activate usrp`) |
|---|---|
| **USRP_study_yishen** | build each `NN-…/apps` (`cmake .. && make`) or run the Python tools — see each project's `notes/run-steps-sy.md`. `git submodule update --init --recursive` only if you need the UHD/GNU Radio **source** (several GB; study/FPGA, not for running host apps). GRC flowgraphs: `grc grc/B200_SpecAna.grc`. |
| **LRLocal-V2** | MATLAB side needs **MATLAB** (manual, below). Python branch: `jupyter notebook` inside `03-tag-template-gen-code/`. |
| **FT232_SCAN_IO** | plug in the FT232H, `jupyter notebook` the project's `Test.ipynb`. Verify the board: `python -c "from pyftdi.ftdi import Ftdi; Ftdi.show_devices()"`. |
| **RTK_dev_for_cm-loc** | `python relposned_monitor.py --mode web --port /dev/cu.usbmodemXXXXXX`. |
| **Saleae Logic** (tool) | `logic2-automation` Python API is in the env; capture runs in the **Logic 2 desktop app** (manual install, below). |
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
  analyzer (the `logic2-automation` pip package in the `usrp` env only *drives* it).
  Install from <https://www.saleae.com/downloads/>; enable the Automation server
  in its Preferences to use the Python API.

## Remote access (step 040)

Run `./setup-040-ssh-remote.sh` **as your normal user** (it calls sudo itself).
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
- **Field-fleet shortcuts + offline-mini internet:** run `host-000-ssh-config.sh`
  once on the operator laptop → `ssh ddh-mac-0X` shortcuts with a reverse SOCKS
  forward, so the mini can `gitp pull` through the laptop's internet
  (FIELD-RUNBOOK §4; helpers installed on the mini by step 040).
- **Screen Sharing (GUI):** connect to `vnc://<ip>` (Finder ▸ Go ▸ Connect to
  Server, or the Screen Sharing app). Needed for GRC, Jupyter, MATLAB GUIs.
  If the script's `launchctl` path is refused, enable **Screen Sharing** in the
  same *System Settings ▸ General ▸ Sharing* pane.
- **Off-LAN** access additionally needs router port-forwarding or a VPN.

## Notes
- Apple-Silicon (`arm64`) assumed throughout (Miniconda + libusb downloads).
- Re-running `setup-000-all.sh` after editing `env/usrp-env.yml` updates the conda
  env in place (`conda env update --prune`).
