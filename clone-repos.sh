#!/usr/bin/env bash
# clone-repos.sh — clone the 4 private project repos into a workspace dir.
#
# Self-contained GitHub auth: installs `gh` if missing, runs `gh auth login`
# (interactive — browser or token) if not logged in, and wires plain `git` to the
# token via a file credential store (works over SSH; see RUNBOOK.md §3). Then clones.
#
# Usage:
#   ./clone-repos.sh                 # clone into the PARENT dir of this kit (../)
#   ./clone-repos.sh /path/to/dir    # clone into a chosen dir
#   WITH_SUBMODULES=1 ./clone-repos.sh   # also pull USRP's uhd+gnuradio source (GBs)
set -u

# Default workspace = the directory ONE LEVEL UP from this kit (i.e. ../), so the
# repos sit as siblings of LRLocal-Mac-EnvSetup — not in a separate ~/Projects.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${1:-$(cd "$HERE/.." && pwd)}"

say()  { printf '\n\033[1;36m[clone] %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }

REPOS=(FT232_SCAN_IO LRLocal-V2 USRP_study_yishen RTK_dev_for_cm-loc)

# ── Ensure gh is installed (download the Apple-Silicon binary if missing) ─────
GH="$HOME/.local/bin/gh"; command -v gh >/dev/null 2>&1 && GH=gh
if ! "$GH" --version >/dev/null 2>&1; then
  say "Installing GitHub CLI (gh) to ~/.local/bin"
  VER="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | sed -nE 's/.*"tag_name": *"v?([^"]+)".*/\1/p' | head -1)"
  ARCH="arm64"; [ "$(uname -m)" = "x86_64" ] && ARCH="amd64"
  if curl -fsSL -o /tmp/gh.zip "https://github.com/cli/cli/releases/download/v${VER}/gh_${VER}_macOS_${ARCH}.zip" \
     && (cd /tmp && unzip -oq gh.zip); then
    mkdir -p "$HOME/.local/bin" && cp "/tmp/gh_${VER}_macOS_${ARCH}/bin/gh" "$HOME/.local/bin/gh"
    GH="$HOME/.local/bin/gh"; ok "gh $VER installed"
  else
    warn "Could not download gh. Install it manually, then re-run."; exit 1
  fi
fi

# ── Ensure logged in (interactive: browser or token) ──────────────────────────
if ! "$GH" auth status >/dev/null 2>&1; then
  say "GitHub login needed — launching 'gh auth login'"
  warn "Choose: GitHub.com → HTTPS → 'Login with a web browser' (or paste a token)."
  "$GH" auth login || { warn "gh auth login failed/cancelled. Re-run when ready."; exit 1; }
fi
ok "gh authenticated"

# ── Wire plain git to the token (file store — works over SSH, not the Keychain)
TOKEN="$("$GH" auth token 2>/dev/null || true)"
if [ -n "$TOKEN" ]; then
  USERN="$("$GH" api user --jq .login 2>/dev/null || echo Worshisy)"
  printf 'https://%s:%s@github.com\n' "$USERN" "$TOKEN" > "$HOME/.git-credentials"
  chmod 600 "$HOME/.git-credentials"
  git config --global --unset-all credential.helper 2>/dev/null || true
  git config --global --add credential.helper '' 2>/dev/null || true
  git config --global --add credential.helper store 2>/dev/null || true
  ok "git credential store set (~/.git-credentials) — plain 'git clone/pull' will work too"
fi

CLONE() { "$GH" repo clone "Worshisy/$1" "$WORKSPACE/$1"; }

say "Workspace: $WORKSPACE"
mkdir -p "$WORKSPACE" || { warn "cannot create $WORKSPACE"; exit 1; }

for r in "${REPOS[@]}"; do
  say "Cloning $r"
  if [ -d "$WORKSPACE/$r/.git" ]; then
    ok "already cloned — pulling"
    git -C "$WORKSPACE/$r" pull --ff-only || warn "pull skipped"
  else
    CLONE "$r" && ok "cloned $r" || { warn "clone failed: $r"; continue; }
  fi
done

# USRP submodules (uhd + gnuradio upstream SOURCE) are large and only needed for
# studying the source / building FPGA bitstreams — NOT for running the host apps.
if [ "${WITH_SUBMODULES:-0}" = "1" ] && [ -d "$WORKSPACE/USRP_study_yishen/.git" ]; then
  say "Pulling USRP submodules (uhd + gnuradio source — several GB)"
  git -C "$WORKSPACE/USRP_study_yishen" submodule update --init --recursive || warn "submodule init failed"
else
  warn "Skipped USRP uhd/gnuradio submodule source (run with WITH_SUBMODULES=1 if you need it)."
fi

say "Done. Repos in: $WORKSPACE"
ls -1 "$WORKSPACE"
