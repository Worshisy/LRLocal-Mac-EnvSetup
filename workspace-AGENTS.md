# AGENTS.md — LRLocal field-measurement workspace (all repos)

> **Review status:** ⏳ Unreviewed *(default; update when Yi reviews)*
>
> ✍️ *Claude-authored (2026-08-03).* Read this FIRST if you are an agent managing
> the whole project hands-on. It maps every repo in this workspace, the field
> system they form, and the conventions Yi expects. Deeper truth lives in each
> repo's own `AGENTS.md`/`README` — this file is the top-level index and the
> cross-repo handoff log.

## What this project is

A field RF-localization measurement system ("LRLocal"): a **TX beacon**
(Raspberry Pi + USRP B210, 2.55 GHz chirped beacon) is received by a **fleet of
RX stations** (Mac minis + USRP B200, continuous 50 MS/s capture to SSD), each
with **RTK-GNSS positioning** (u-blox rover + base corrections). Offline
**MATLAB analysis** (detection / TDoA) runs on the captures. Everything is
operated headless in the field over per-unit Wi-Fi APs + SSH.

## Workspace map — the repos (siblings of this file)

| Repo | Language | Role | Read first |
|---|---|---|---|
| `LRLocal-Mac-EnvSetup/` | bash | **The ops kit.** Machine setup (`setup-0X0-*`), day-to-day field jobs (`field-0X0-*`), operator laptop config (`host-000-*`), Pi TX box config (`pi-000-*`). Cloned everything else. | `README.md`, `SETUP-RUNBOOK.md`, `FIELD-RUNBOOK.md` |
| `USRP_study_yishen/` | C++/CMake (UHD), some Python, FPGA/Verilog | USRP host apps. Key: `01-rx-to-ssd-b200-agc/` (the RX capture app: sw-AGC, sc12, PSD sidecars) and `11-tx-beacon-usrpb200-code/` (the TX beacon that runs on the Pi as systemd service `tx-beacon-b200mini`). `uhd/`+`gnuradio/` submodules = study source only. | its `AGENTS.md`, each project's `notes/run-steps-sy.md` |
| `LRLocal-V2/` | MATLAB (`01-system-analysis-code/`, `02-field-detection-code/`), Python/Jupyter (`03-tag-template-gen-code/`) | The analysis & detection pipeline (Case B decimated FFT detector etc.). Needs MATLAB + Signal Processing + Parallel Computing toolboxes. | `START.md`, its `AGENTS.md` |
| `RTK_dev_for_cm-loc/` | Python | RTK rover monitor: `relposned_monitor.py` (web dashboard :8000, per-session CSV/debug logs). | its `AGENTS.md` / README |
| `FT232_SCAN_IO/` | Python/Jupyter | Chip scan-chain IO via FT232H. **Cloned once, deliberately excluded from `field-010-update-repos.sh`.** | its README |

Layout note: on the field minis all repos sit flat next to this file (and next
to the kit). On Yi's master Mac, `USRP_study_yishen` is nested one level down
(`USRP/USRP_study_yishen`) — the kit's scripts autodetect both (plus
`/Volumes/USRP*`); use `REPO_BASE=` to override.

## The deployed system (who is what)

| Unit | Access | Runs |
|---|---|---|
| Mac minis 01–06 (`ddh-macmini4-0X`) | own Wi-Fi AP `macmini-field-0X` (pw `eecs2435`) → `ssh ddh-mac-0X` = `192.168.2.1` | RX capture, RTK monitor, PSD viewer :8081, file browser :8082 — all via `field-000-jobs.sh` in tmux |
| Raspberry Pi beacon box (`user`) | AP `ddh-pi4-beacon` → `ssh ddh-pi4-beacon` = `192.168.3.1` | TX beacon as systemd service (60 s warmup at every start); bashrc shortcuts `gitpull` / `tx_freq` / `tx_status` / `tx_restart` / `pi_restart`, menu printed at login |
| Operator Mac/laptop | joins one AP at a time | `host-000-ssh-config.sh` installs the shortcuts; **every ssh carries a reverse SOCKS tunnel (`RemoteForward 1080`)** — the offline units git-pull/install through the operator's internet |

Everything field-critical self-recovers on power-cycle: AP autostart, TX
service, never-sleep. Clocks self-sync through the tunnel (no NTP off-grid).

## Operating it (agent cheat-sheet)

- Update a unit: `field-010-update-repos.sh` (ff-only, via tunnel; prints triage
  when a pull is blocked). Pi: `gitpull` (its clones use the SSH remote → needs
  the ProxyCommand form, see FIELD-RUNBOOK §4b).
- Run/watch field jobs: `field-000-jobs.sh start|attach|logs|data|status|stop`.
  `data rtk` tails the newest RTK session CSV. Dashboards: :8000 RTK, :8081 PSD,
  :8082 files.
- Wipe captures: `field-020-empty-rx-data.sh` (lists records, pick keeps, y+y).
- Change TX freq: on the Pi, `tx_freq 2.55` (GHz; edits run.conf + restarts the
  service). RX freq is asked (in GHz) at every `start rx`.
- Data conventions: rx captures → `USRP_study_yishen/data/<UTC>/` (sc12 +
  run.log + run_meta + gain_log + psd/); RTK sessions →
  `RTK_dev_for_cm-loc/data/<UTC>/relposned_*.{csv,debug.log}`; `../rx-data`
  symlink points at the rx data root.

## Conventions Yi expects from every agent (short form)

1. Read the target repo's own `AGENTS.md` before working in it; append handoff
   notes there (and cross-repo ones here) — agents can't message each other.
2. Minimal, style-matched diffs; mark new/changed source lines `# [c]` (transient
   review scaffolding Yi strips after review). Don't rewrite validated code.
3. Claude-authored docs carry a `> **Review status:**` badge (⏳/👀/✅).
4. Never report a number you didn't read from a run/log this session.
5. Ask before pushing anything Yi modified; never force-push main.
6. Don't touch `11-tx-beacon-usrpb200-code` internals or FT232_SCAN_IO without
   an explicit ask. Sub-agent model choice: ask Yi.
7. Hardware gotchas that bit before: USB over-current when the B210 shares a bus
   with the RTK rover (radio firmware load fails → no LED); B210 wants external
   DC / powered hub under sustained TX; Spotlight must stay off capture SSDs;
   a full SSD kills both captures and git pulls.

## State snapshot (2026-08-03 — update when it changes)

- System frequency: **2.55 GHz** (TX run.conf + RX capture confirmed on-air).
- mac-02, mac-03: updated, dry-run verified (RX clean at 150 MB/s, AGC 73 dB,
  no clipping). mac-03 rover attached and streaming epochs; mac-02 rover NOT
  plugged in. mac-04/05/06: powered but their APs never appeared — need
  hands-on (step 060 / Internet Sharing check).
- Pi beacon: healthy after rewiring (12+ min clean, U=T=S=0); watch for the
  USB wedge signature (`short send: 0` + frozen sample counter behind an
  "active" service). Proposed-but-not-applied: watchdog exit in 11-tx.
- FT232_SCAN_IO on mac-02: 37 commits behind + dirty (Jul-28 debris), awaiting
  Yi's decision.

## Handoff log (newest first — append here)

- **2026-08-03 (Claude, operator Mac):** created this file. Fleet update swept
  (02✓ 03✓, 04–06 unreachable). Simplified capture-wipe flow. PSD viewer +
  file browser added as field jobs. Pi TX wedge diagnosed as USB power; fixed
  by Yi's rewiring.
