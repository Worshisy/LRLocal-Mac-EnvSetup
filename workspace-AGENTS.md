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
| `LRLocal-Mac-EnvSetup/` | bash (+ PowerShell for Windows operators) | **The ops kit.** Machine setup (`setup-0X0-*`), day-to-day field jobs (`field-0X0-*`), operator laptop config (`host-00X-*`), Pi TX box config (`pi-000-*`). Cloned everything else. | its `AGENTS.md` (kit conventions + agent traps), `README.md`, `FIELD-RUNBOOK.md` |
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
| Mac minis 01–06 (`ddh-macmini4-0X`) | own Wi-Fi AP (pw `eecs2435`) — SSID is `macmini-field-0X` on 03 but **`ddh-macmini4-0X` on 02/05** (mixed convention, observed 2026-08-05) → `ssh ddh-mac-0X` = `192.168.2.1` | RX capture, RTK monitor, PSD viewer :8081, file browser :8082 — all via `field-000-jobs.sh` in tmux |
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
  :8082 files (incl. `/beacon-checks/` — the `beacon` job's 5-min/hourly
  beacon-RX verifier verdicts + figures; tool in
  `USRP_study_yishen/02-rx-beacon-verify/`).
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

## State snapshot (2026-08-05 — update when it changes)

- System frequency: **2.55 GHz** (TX run.conf + RX capture confirmed on-air).
- 2026-08-05 mac-03 run evaluated (see `data/20260805-run-eval/RESULTS.md`):
  beacon TX/RX verified (25 ms grid ±1 sa, chirp 59 dB); RTK lost FIX after
  2.5 min (then ~1 m FLOAT/DGNSS).
- Preamble mystery RESOLVED on the Pi (08-05 pm): code/binary/config all
  verified correct end-to-end (byte-identical rebuild + self-RX loopback,
  rho 0.86); the scrambled preamble was a latched TX-chain state. Corrected
  timeline (Pi clock runs ~17–21 h behind — anchor before trusting log
  stamps!): the on-air-during-capture instance logged **T=14,224 time errors
  in 19 h (0.21/s)**; three consecutive instances stayed bad across two
  service restarts; cleared only by deeper re-init (UHD sessions + Pi
  reboot). Health rule: **T rate ≳1/min sustained → power-cycle the
  Pi/B200** (healthy baseline ≈0.003/s; `tx_restart` alone does NOT clear
  it). Beacon OTA-verified from mac-02 (rect template 46 dB on 80/80
  packets, chirp 61 dB, grid ±1 sa) — incident CLOSED.
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

- **2026-08-05f (Claude, master Mac):** Task 3 built: `USRP_study_yishen/`
  **`02-rx-beacon-verify/`** — field beacon checker (quick 100 ms / full 20 s,
  nohup-detached, nice-19, results to `<volume>/beacon-checks/` for the :8082
  browser; `repeat-check.sh` 5-min/hourly daemon; `host-check.sh` interactive).
  Validating it **overturned the 05c/05d incident story**: the morning capture
  was a MIX — 66/80 packets perfectly healthy rect seed-0 @ CFO +750 Hz,
  14/80 one identical unknown junk preamble (clustered), chirps valid in all
  → **intermittent per-burst TX fault, not a latched session state**; "restart
  fixed it" is unproven (afternoon window may have sampled clean). Morning
  analyses were defeated by CFO-nulling of circular corr + anchor parity;
  details in RESULTS.md "REVISED" section. The tool's per-packet
  `preamble_ok_frac` is the monitor (WARN + junk indices on mixed captures —
  verified against both captures). Junk identity: not seeds/RRC/transforms/
  byte-mangles — open. Deployed + verified on mac-02 (numpy/matplotlib wheel
  drop for system py3.9.6; live-capture test: quick 1.1 s / full 30 s PASS
  beside rx at 150 MB/s with **ovf=0 drops=0 throughout**; repeat daemon
  running as field-000 tmux job `beacon`; host-check verified end-to-end).
  mac-05: AP up (SSID `ddh-macmini4-05`) but **rejects the operator ssh key**
  — needs Yi to `ssh-copy-id` once, then the same deploy. mac-02 agent trap:
  tmux is in the conda usrp env (bare ssh shells miss it), and nohup'd
  ssh-spawned writes to /Volumes/USRP02 hit TCC EPERM — the tmux/field-000
  path writes fine, so no setup-040 needed for this. Note: mac-02's
  Aug-4 capture shows 20/20 healthy preambles — junk-burst rate is
  time-varying, reinforcing the need for the repeat monitor.

- **2026-08-05e (Claude, Pi AP):** Pi clock + file-browser hardening (per Yi,
  after the clock-offset confusion in 05c/05d). Live on the Pi AND in the kit
  (`pi-000-hotspot.sh`, `host-000-ssh-config.sh`, marked `# [c]`, not pushed):
  (1) `~/bin/lrl-timesync.sh` shared by the bashrc login hook and a NEW
  `~/.ssh/rc` hook — internet time sync now fires on EVERY ssh/scp (throttled
  10 min, silent); (2) no-internet fallback: host-000's ssh config now pushes
  the operator PC's clock via LocalCommand on every connection (≥2 s gate;
  verified: +300 s skew corrected to ±1 s by one plain ssh); (3) web file
  browser on the Pi at `http://192.168.3.1:8082` serving `~` (python
  http.server, cron @reboot + 5-min ensure-alive — no sudo for a systemd
  unit). Yi's ~/.ssh/config on the operator Mac updated live (inside the
  managed block; re-running host-000 reproduces it).
- **2026-08-05d (Claude, mac-02 AP):** OTA re-verify after Yi restarted the
  beacon: mac-02 15 s capture → rect seed-0 template 46.2 dB on all 80 packets
  (CFO +1975 Hz = +0.77 ppm), grid 79/79 ±1 sa, chirp 60.9 dB with clean +100
  stairstep; the corrupted-session learned template now scores chance (11.7 dB).
  Incident closed. Verification capture: mac-02 `/tmp/qpsk-verify/` (transient).
- **2026-08-05c (Claude, on beacon AP):** Root-caused the preamble mismatch
  from 08-05b — NOT a code/build issue. Evidence chain in RESULTS.md follow-up
  section: Pi tree clean, deployed binary byte-identical to fresh build, seed
  tables cpp↔py↔MATLAB all equal; B200 self-loopback of the real binary shows
  a perfect preamble (rho 0.86). Verdict: latched per-session TX anomaly of the
  Aug-4 instance (T=869 in its log). Beacon service left inactive (needs sudo)
  — Yi runs `tx_restart`. Diagnostic harnesses archived in the eval folder.
- **2026-08-05b (Claude, operator Mac):** Evaluated mac-03's newest run
  (RTK `20260805-160538` + RX `20260805-160547`, tasks in `task.md`). Full
  report + plots + scripts: **`data/20260805-run-eval/RESULTS.md`**. Highlights:
  RTK held FIX (2.5 cm horiz std) only the first ~2.5 min, then FLOAT/DGNSS at
  ~1 m with 153 state flaps — not cm-grade as-is; proposed a 5-min rolling
  per-class stats panel for the RTK dashboard (not implemented). Beacon v2
  verified end-to-end on a 2 s slice: 25 ms period exact to ±1 sample (79/79),
  chirp circ-xcorr 59 dB with clean +100 stairstep, −0.334 ppm clock offset.
  ⚠️ Open: on-air QPSK preamble repeats per spec but is NOT the current
  source's Gold sequence (all seeds/transforms/CFO ruled out; synthetic
  self-test validates the method) — suspect the Pi binary was built from a
  modified tree; check Pi build vs repo next time its AP is up. Workaround
  shipped: learned preamble template (43 dB MF peaks), npy in the eval folder.
  Band note: 2.55 GHz gaps are full of LTE/5G-n41-like TDD bursts + deep
  multipath ripple — detection margins must absorb both.
- **2026-08-05 (field agent, mac-03 side):** kit hardening — field-010 one-key
  overwrite flow (OVERWRITE=1 for no-tty), $LRKIT + `kit`/`gitpull` shortcuts
  (setup-040 §3d), LF .gitattributes, Windows operator script (host-001), and
  the kit-level AGENTS.md. Unit 03 fully current.
- **2026-08-03 (Claude, operator Mac):** created this file. Fleet update swept
  (02✓ 03✓, 04–06 unreachable). Simplified capture-wipe flow. PSD viewer +
  file browser added as field jobs. Pi TX wedge diagnosed as USB power; fixed
  by Yi's rewiring.
