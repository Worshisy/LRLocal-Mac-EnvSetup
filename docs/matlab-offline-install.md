# Installing MATLAB (and other big software) on the Off-Grid Field Minis

> **Review status:** 👀 Glanced *(procedure executed end-to-end on mac-02 2026-08-15; Yi activated)*
>
> ✍️ *Claude-authored.* How to install MATLAB on a mini that has **no internet**
> (it hosts the field AP), plus the general offline-install pattern. Verified by
> the R2026a install on mac-02.

## TL;DR — the offline mpm flow (what actually works)

On the **operator laptop** (has internet, joined to the mini's AP on en1):

```sh
curl -sLo /private/tmp/mpm https://www.mathworks.com/mpm/maca64/mpm && chmod +x /private/tmp/mpm
/private/tmp/mpm download --release=R2026a --destination=/private/tmp/matlab-src  --products MATLAB
/private/tmp/mpm download --release=R2026a --destination=/private/tmp/matlab-src2 --products Signal_Processing_Toolbox Parallel_Computing_Toolbox Communications_Toolbox Statistics_and_Machine_Learning_Toolbox
rsync -a /private/tmp/matlab-src/  ddh-mac-0X:matlab-src/
rsync -a /private/tmp/matlab-src2/ ddh-mac-0X:matlab-src2/
```

On the **mini** (no network needed — run in tmux, it takes a while):

```sh
~/mpm install --source=$HOME/matlab-src  --destination=/Applications/MATLAB_R2026a.app --products MATLAB
~/mpm install --source=$HOME/matlab-src2 --destination=/Applications/MATLAB_R2026a.app --products Signal_Processing_Toolbox Parallel_Computing_Toolbox Communications_Toolbox Statistics_and_Machine_Learning_Toolbox
sudo ln -sf /Applications/MATLAB_R2026a.app/bin/matlab /usr/local/bin/matlab
```

Sizes for R2026a + these 4 toolboxes: 1.5 GB (base archives) + 2.0 GB (toolbox
archives) → **5.2 GB installed**. Operator needs only one batch on disk at a time.

## mpm gotchas (each cost a failed attempt)

- **`--release` and `--source` are mutually exclusive** on `mpm install` —
  offline installs use `--source` ONLY (`Error: Invalid option combination`).
- **`mpm download` refuses a non-empty destination** — one folder per batch.
- **Pass-2 add-on installs work**: pointing a second `mpm install --source` at an
  existing `--destination` adds toolboxes into the same MATLAB tree.
- Toolbox set for LRLocal-V2 (from its README + a function scan): Signal
  Processing + Parallel Computing (core: xcorr/findpeaks/resample + parfor
  everywhere), Communications (awgn, pskmod, comm.PhaseNoise/RicianChannel),
  Statistics (prctile, randsample).

## Why not a proxy? (the dead ends — don't repeat)

The mini can reach the internet for `curl`/`git` via the operator's reverse
SOCKS (`RemoteForward 1080`, on-mini helpers `gitp`/`proxyon`). **But mpm (and
other CFNetwork apps) ignore `HTTP_PROXY`/`ALL_PROXY` env vars on macOS** — they
use the *system* proxy. And on a mini the system proxy is a dead end:

- The mini's active interface is the AP bridge (`bridge100`); Wi-Fi service is
  inactive and there is **no default route**, so `networksetup -setwebproxy`
  never reaches the global proxy dict (`scutil --proxy` stays empty) and a
  manual `scutil` write to `State:/Network/Global/Proxies` is instantly reverted.
- Do **not** set a persistent system proxy on a mini anyway — it silently
  reroutes everything if the box ever gets a route, and it broke nothing but
  fixed nothing here (reverted 2026-08-15 on mac-02).

So: env-var proxies work for curl/git; anything CFNetwork-based (mpm, App Store,
MATLAB activation client) needs REAL internet or a fully offline flow.

## Activation / license

- The software installs fine unlicensed; MATLAB asks at first launch.
- **Online (used for mac-02):** give the mini temporary real internet
  (ethernet), launch MATLAB in the remote-desktop session, sign in → activates.
- **Offline alternative:** License Center → "Activate a Computer" with the
  mini's Host ID = its `en0` MAC (`ifconfig en0 | awk '/ether/{print $2}'`,
  e.g. mac-02 `1c:f6:4c:6a:83:a6`) + login name → download `.lic` → drop into
  `/Applications/MATLAB_R2026a.app/licenses/`. No network ever needed.
- Campus-license note: "Unable to link the university license" in License
  Center usually means the MathWorks account isn't on the university email or
  the Online Services Agreement wasn't accepted; otherwise it's an
  admin-side attribute (contact the license admin).

## Same pattern for other software (verified examples)

Anything the mini needs gets downloaded on the operator and pushed over the AP:

- **VS Code**: `curl -L https://update.code.visualstudio.com/latest/darwin-arm64/stable`
  → ditto/zip to `/Applications`, `xattr -dr com.apple.quarantine`, symlink
  `.../Resources/app/bin/code` → `/usr/local/bin/code`.
- **VS Code extensions** (marketplace is unreachable from the mini): download
  `.vsix` on the operator via the marketplace `extensionquery` API — downloader
  script: session scratchpad `fetch_vsix_field.py` (picks **darwin-arm64**
  builds for platform-specific extensions — cpptools, vscode-xml need it) —
  then `code --install-extension file.vsix` over ssh. Installed set for the
  field repos: Python+Jupyter (+debugpy, pylance), MATLAB, Verilog/SystemVerilog
  (mshr-h.veriloghdl), YAML, even-better-toml, cpptools, vscode-xml.
- **RustDesk**: arm64 dmg → hdiutil attach → cp -R to /Applications (see
  `remote-desktop-m4.md`).

## Per-machine registry

| mini | MATLAB | toolboxes | activated |
|---|---|---|---|
| mac-02 | R2026a @ /Applications/MATLAB_R2026a.app | Signal, Parallel, Comm, Stats | ✅ 2026-08-15 (Yi, online) |
| mac-03/05/06 | — | — | repeat this runbook |
