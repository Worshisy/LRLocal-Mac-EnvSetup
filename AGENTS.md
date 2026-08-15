# AGENTS.md — orientation for AI agents working on this kit

> **Review status:** ⏳ Unreviewed *(default; update when Yi reviews)*
>
> ✍️ *Claude-authored (2026-08-05).* Written so an agent on another machine —
> a Mac operator laptop, or a session picking this repo up cold — knows the
> layout, the conventions, and the traps that already cost a debug round here.
> Human docs stay authoritative: [README.md](README.md) (what the kit sets up),
> [SETUP-RUNBOOK.md](SETUP-RUNBOOK.md) (build a fresh mini),
> [FIELD-RUNBOOK.md](FIELD-RUNBOOK.md) (operate one in the field).
> **Whole-project map** (all sibling repos — USRP C++ apps, MATLAB analysis,
> RTK monitor — plus the deployed system and cross-repo handoff log): the
> workspace-level **`../AGENTS.md`**, seeded from
> [workspace-AGENTS.md](workspace-AGENTS.md) by `setup-030-clone-repos.sh`.

## 1. Who runs what, where

Four machine roles. Getting this wrong is the most common mistake — a script
run on the wrong box either fails loudly or silently configures nothing.

| Prefix | Runs on | Notes |
|---|---|---|
| `setup-*` | a fresh Mac mini | once, in numeric order (`setup-000-all.sh` orchestrates) |
| `field-*` | a Mac mini | day-to-day: jobs, updates, wiping captures |
| `host-*` | the operator laptop | `host-000` = macOS/Git Bash, `host-001` = Windows |
| `pi-*` | the TX Raspberry Pi | its own AP on a separate subnet |

Naming is `<role>-XXX-<name>.sh`, `XXX = 0<step><sub>`; sub digit `0` is the
step's main script, `1–9` are sub-functions of it.

**The operator side runs on both Windows and macOS.** Never assume a POSIX
host: see §5 for what that costs.

## 2. Field topology

Minis and the Pi are offline in the field and broadcast their own APs:

| | Address | Reached as |
|---|---|---|
| mini 0X | `192.168.2.1` (each unit reuses it) | `ssh ddh-mac-0X` → `ddh-macmini4-0X@192.168.2.1` |
| TX Pi | `192.168.3.1` | `ssh ddh-pi4-beacon` → `user@192.168.3.1` |

Both shortcuts come from `host-000-ssh-config.sh`, which also sets
`RemoteForward 1080` — a **reverse SOCKS proxy**: the offline mini reaches the
internet *through the operator's machine*. Every git pull on a mini rides that
tunnel (`gitp`, `proxyon`, or `field-010`'s `-c http.proxy=…`). Because each
unit reuses `192.168.2.1` with its own host key, the managed block deliberately
sets `StrictHostKeyChecking no` + `UserKnownHostsFile /dev/null` for those
hosts — that is intentional, not sloppiness; do not "fix" it.

**The kit is not in `$HOME` on a mini.** It is cloned onto the capture SSD,
e.g. `/Volumes/USRP03/LRLocal-Mac-EnvSetup`. Step 040 pins that as `$LRKIT`
and installs `kit` (cd there) and `gitpull` (run `field-010`) into `~/.zshrc`.

## 3. Conventions to follow when editing

- **Idempotent managed blocks.** Anything written into a user's `~/.zshrc`,
  `~/.bashrc`, or `~/.ssh/config` goes between `# >>> LRLocal … >>>` /
  `# <<< LRLocal … <<<` markers, and the script strips the old block by its
  **stable prefix** before appending — so a block written under an older script
  name is replaced, never duplicated. Copy that pattern; don't invent another.
- **`# [c]` comments** mark a deliberate, non-obvious choice (and often who and
  when). Keep them, and add one when a line would otherwise look arbitrary.
- **bash 3.2.** macOS ships it. No `mapfile`, no associative arrays, no `${x^^}`.
  `set -u` is on: empty arrays bite, which is why `PROXY_OPTS` is a plain string.
- **Never break the no-TTY path.** Agents, `ssh host 'cmd'`, and cron have no
  terminal. Interactive prompts must be guarded with `[ -t 0 ]` and offer an
  env-var opt-in (`OVERWRITE=1`) instead of silently doing the destructive thing.
- **Never `git clean` a repo wholesale.** Capture data sits untracked inside
  them. When clearing blockers, remove only the paths git named.
- **LF endings.** `.gitattributes` forces `*.sh` / `*.py` to LF; a CRLF script
  copied to a mini dies with `env: bash\r: No such file or directory`.
- **Doc banner.** New `.md` files carry the review-status + ✍️ *Claude-authored*
  header used by every other doc here.
- **Commits** are `area: imperative summary`, with a body explaining *why* when
  the reason isn't obvious from the diff.

## 4. Driving a mini from an agent session

Password prompts need a TTY, so an agent needs key auth: append the operator's
public key to `~/.ssh/authorized_keys` on the mini once. **`authorized_keys` is
per operator machine** — a unit reachable from the Mac is not automatically
reachable from the Windows PC, so state which key you mean:

| Operator machine | Key present on |
|---|---|
| Windows PC (`yi-shen-lggram16-field-ops`) | units **02, 03** — both verified with `BatchMode=yes` on 2026-08-05 |
| Mac laptop | units 02, 03 + the TX Pi (per the Mac session, 2026-08-03) |

Units 01, 04–06 have neither.

```sh
ssh -o BatchMode=yes ddh-mac-03 'cd "$LRKIT" && git log --oneline -1'
```

- **Port 1080 is single-occupancy.** If the operator already has an interactive
  session, a second connection can't bind it and warns
  `remote port forwarding failed for listen port 1080` — harmless. Use a second
  port for agent work: `ssh -R 1081 …` plus `PROXY=socks5h://127.0.0.1:1081`.
  A `sshd-sess` left by an ungracefully-dropped session holds 1080 too; check
  with `lsof -nP -iTCP:1080 -sTCP:LISTEN`, and **never** kill a PID equal to
  your own shell's `$PPID`.
- **The remote shell is zsh.** Unquoted `[HEAD]` globs and fails
  (`no matches found`), and a leading `=` triggers EQUALS expansion
  (`zsh:1: == not found`). Use plain `echo WORD:` markers in remote commands.
- **Windows PowerShell 5.1 strips embedded double quotes** when calling native
  exes, so `ssh host 'grep -E "a|b" f'` arrives as a *pipeline* and hangs
  reading stdin. Drive remote commands from Git Bash, or pipe a heredoc into
  `ssh host 'bash -s'`.
- **Verify against a real unit before claiming a fix works.** Roll a repo back
  (`git reset --hard <sha>~1`), dirty a file the newer commit touches, and run
  the script — both the refusing path and the confirming path.

## 5. Windows-operator traps (all three fail silently or misleadingly)

Run `host-001-ssh-config-windows.ps1` on Windows instead of `host-000` directly;
it calls host-000 through Git Bash and then repairs:

1. **ACLs.** host-000 rewrites `~/.ssh/config` via `mktemp`+`mv`, so the file
   inherits group access and `ssh.exe` refuses it outright — *Bad owner or
   permissions*. Its `chmod 600` means nothing on NTFS. **Re-apply after every
   host-000 run**, not once.
2. **An `ssh -F <file>` profile wrapper** (e.g.
   `function ssh { & ssh.exe -F "C:\ssh\ssh_config.txt" @args }`) makes that
   file win over `~/.ssh/config`, so the field shortcuts are invisible:
   *Could not resolve hostname ddh-mac-03*. The fix is an `Include`, which has
   two non-obvious requirements — it must sit **above the first `Host` block**
   (otherwise it is scoped to the preceding host), and the path needs **forward
   slashes**, because `Include` is `glob()`ed and `glob()` treats `\` as an
   escape, so a backslash path matches nothing and reports no error.
3. **A `-F` config outside `~/.ssh`** inherits `C:\`'s ACL, letting every local
   account modify it. OpenSSH does **not** permission-check `-F` files, so a
   `ProxyCommand` planted there runs as the operator with no warning.
   Tightening it needs an elevated run.

**`icacls` trap that locked the operator out (2026-08-05).** Never push
`(OI)(CI)` grants onto files:

```powershell
icacls C:\ssh /inheritance:r /grant:r "user:(OI)(CI)F" ... /T   # BREAKS child FILES
```

`(OI)(CI)` are *container* inheritance flags. With `/T`, `icacls` strips each
child file's inherited ACEs, cannot apply container-flagged grants to a file,
and reports **success** while leaving the file with an **empty DACL** — nobody,
not even the owner, can read it, and ssh dies with `Can't open user config
file …: Permission denied`. Correct form: flag the directory only (no `/T`),
then let children inherit.

```powershell
icacls C:\ssh /inheritance:r /grant:r "user:(OI)(CI)F" "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F"
icacls C:\ssh\* /reset /T
```

Recovery, if it already happened: `takeown /f <dir> /r /d y` (elevated) makes
you the owner, and an owner can always rewrite a DACL — then `icacls <file>
/reset` restores inherited rights. `host-001` now verifies readability after
every ACL change and reverts itself if the file became unreadable.

## 6. State as of 2026-08-05

Changed 2026-08-05 evening (Claude, uncommitted `# [c]` edits — Yi to review):

- `field-000-jobs.sh` — new **`beacon` job** (5th job, in start-all/stop):
  runs `USRP_study_yishen/02-rx-beacon-verify/repeat-check.sh run-fg` in tmux
  — beacon-RX verifier, quick every `BEACON_QUICK_MIN` (5) min + full every
  `BEACON_FULL_MIN` (60) min; results → `<volume>/beacon-checks/` (in the
  :8082 browser). RX-safety verified live on mac-02 (150 MB/s capture,
  ovf=0 throughout). Needs numpy on the mini (`02-rx-beacon-verify/
  setup-env.sh`; offline wheel-drop recipe in its header — done on mac-02).
  FIELD-RUNBOOK §3 documents the job. **Running on mac-02 now** (tmux session
  `beacon` via this script — tmux lives in the conda usrp env; `command -v
  tmux` in a bare ssh shell misses it, the script's fallback finds it).
  One real gotcha: processes nohup'd from a bare ssh shell get TCC EPERM
  writing /Volumes/USRP02 (agent trap — the tmux/field-000 path writes fine,
  see 02's existing capture dirs). Also observed: mini APs on 02/05 broadcast
  SSID `ddh-macmini4-0X` (not `macmini-field-0X`), and with both APs known,
  macOS auto-roams between them — both answer at 192.168.2.1, so ssh
  "connection closed" usually means you're on the other mini's AP.

- `pi-000-hotspot.sh` — Pi time-sync overhaul: shared `~/bin/lrl-timesync.sh`
  (bashrc login hook now a thin wrapper) + a `~/.ssh/rc` hook so the internet
  sync fires on EVERY ssh/scp connection (10-min throttle; rc stays silent —
  stdout there corrupts scp). Plus a web file browser on `:8082` serving `~`
  (cron `@reboot` + 5-min ensure-alive; no sudo for systemd on the Pi). Both
  applied live on the beacon Pi and verified (HTTP listing OK; sync drift 1 s).
- `host-000-ssh-config.sh` — the Pi host block now carries `PermitLocalCommand`
  + `LocalCommand`: every operator ssh **pushes the PC's clock** to the Pi
  (≥2 s drift gate, recursion-guarded) — covers the no-internet field case.
  Heredoc escaping verified by sandbox-running the script and diffing against
  the live, tested config. Live-applied to Yi's operator Mac.
  Why all this: the Pi clock ran 17–21 h behind on 08-05 and scrambled the
  log-timeline analysis of the beacon TX incident (see workspace AGENTS 05c).

Changed this session (`d03a605`, `acf2eab`, `a91605e`, `29b1798`):

- `field-010-update-repos.sh` — a repo whose local edits block the `--ff-only`
  pull now prints `diff --stat` and asks **once** whether to overwrite with the
  GitHub version; resets to the tracking ref (`@{u}`), not a hardcoded
  `origin/main`. No prompt without a TTY: `OVERWRITE=1` pre-confirms.
- `setup-040-ssh-remote.sh` — installs `$LRKIT` + `kit` / `gitpull`.
- `.gitattributes` — LF for `*.sh` / `*.py`.
- `host-001-ssh-config-windows.ps1` — new Windows operator entry point.

Outstanding:

- Units **01, 02, 04–06**: pull the kit, then run `./setup-040-ssh-remote.sh`
  once each (needs sudo, so interactive — a pull alone does not add `gitpull`).
  Add the operator public key to each if agents should drive them.
- Unit 03 is current (`29b1798`), clean, and needs nothing.
- `/Volumes/USRP03` was at 539 GiB free (72% used) and falling during captures;
  a full disk is what kills a pull mid-checkout.

## 2026-08-14 — GPS-first clock sync + link file (Claude, authored on mac-05)

- `rtk-010-gps-sync-once.sh` — one-shot host-clock step from the RTK receiver
  (RMC/NAV-PVT), run by `field-000-jobs.sh start` BEFORE any job; never re-steps,
  so host↔GPS stays one fixed relationship per session. Falls back to
  `sync_time_via_tunnel` when no receiver/fix. `RTK_SYNC=skip` bypasses. Macs
  only — the Pi keeps its ssh-hook sync.
- `rtk-011-make-gps-link.py` — writes `gps_host_link.csv` (offset + drift fit)
  from a session relposned csv; rx chain and rtk logger untouched.
- Commit 0ea6b10 exists ONLY on mac-05 (minis off-grid); push to origin from an
  internet-connected node, then propagate to 02/06 (bundle) after the outdoor
  GPS test on mac-05 validates the fix path.

## 2026-08-15 — Remote desktop on M4 field minis (Claude)

Headless Apple-Silicon (M4) minis: generic VNC renders BLACK; use **Screen Sharing.app**
(Mac) and **RustDesk** direct-IP (Windows). Full runbook + gotchas (dummy plug required,
"Screen Sharing is not permitted" = must enable via System Settings GUI not CLI, RM vs
Screen Sharing conflict, persist-on-disconnect via console session):
**docs/remote-desktop-m4.md**. mac-02 set up live 2026-08-14/15 (RustDesk ID 429722566).

## 2026-08-15 — MATLAB + offline software installs on the minis (Claude)

MATLAB R2026a + Signal/Parallel/Comm/Stats toolboxes installed on mac-02
(/Applications/MATLAB_R2026a.app, `matlab` CLI linked; Yi activated online).
Runbook + gotchas in **docs/matlab-offline-install.md** — key facts: minis have
no internet, so use `mpm download` on the operator + `mpm install --source` on
the mini (offline); mpm/CFNetwork apps IGNORE env-var proxies and the minis
cannot take a system proxy (AP bridge, no default route) — do not try, and do
not set persistent system proxies on minis. Same operator-download pattern for
VS Code (+offline .vsix extensions) and RustDesk.
