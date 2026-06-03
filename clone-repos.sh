#!/usr/bin/env bash
# clone-repos.sh — clone the 4 private project repos into a workspace dir.
#
# Requires GitHub auth first (gh auth login, or git credentials / SSH key with
# access to the Worshisy org). See RUNBOOK.md §3.
#
# Usage:
#   ./clone-repos.sh                 # clone into ~/Projects
#   ./clone-repos.sh /path/to/dir    # clone into a chosen dir
#   WITH_SUBMODULES=1 ./clone-repos.sh   # also pull USRP's uhd+gnuradio source (GBs)
set -u

WORKSPACE="${1:-$HOME/Projects}"
GH="$HOME/.local/bin/gh"; command -v gh >/dev/null 2>&1 && GH=gh

say()  { printf '\n\033[1;36m[clone] %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }

REPOS=(FT232_SCAN_IO LRLocal-V2 USRP_study_yishen RTK_dev_for_cm-loc)

say "Workspace: $WORKSPACE"
mkdir -p "$WORKSPACE" || { warn "cannot create $WORKSPACE"; exit 1; }

# Verify GitHub access once.
if "$GH" auth status >/dev/null 2>&1; then
  ok "gh authenticated"
  CLONE() { "$GH" repo clone "Worshisy/$1" "$WORKSPACE/$1"; }
else
  warn "gh not authenticated — falling back to git over HTTPS (needs a credential helper or PAT)."
  CLONE() { git clone "https://github.com/Worshisy/$1.git" "$WORKSPACE/$1"; }
fi

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
