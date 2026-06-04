#!/usr/bin/env bash
# 60-saleae-venv.sh — direct (non-conda) Python venv for Saleae Logic analyzer.
#
# The Saleae "Logic 2" DESKTOP APP is a manual GUI install from saleae.com (it
# does the actual capture and talks to the hardware). This venv adds the Python
# AUTOMATION API (`logic2-automation`) which drives Logic 2 over a local socket
# for scripted captures/exports + the usual sci stack for post-processing.
set -u

VENV="$HOME/venvs/saleae"

say()  { printf '\n\033[1;36m[60] %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }

say "Creating venv at $VENV"
mkdir -p "$(dirname "$VENV")"
[ -d "$VENV" ] || python3 -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"
python3 -m pip install --upgrade pip >/dev/null
python3 -m pip install logic2-automation numpy pandas matplotlib jupyter
ok "Installed logic2-automation + sci stack into $VENV"

say "Verifying"
python3 - <<'PY' && ok "saleae automation API imports OK" || warn "import failed"
import numpy
from saleae import automation
print("  saleae.automation import OK | numpy", numpy.__version__)
PY

warn "The CAPTURE software is the 'Logic 2' DESKTOP APP — install it by hand from"
warn "https://www.saleae.com/downloads/ (see RUNBOOK 'manual prerequisites')."
warn "To script it: open Logic 2 ▸ enable the Automation server (Preferences),"
warn "then connect from Python:"
printf '    source %s/bin/activate\n' "$VENV"
printf '    python3 -c "from saleae import automation; m=automation.Manager.connect(); print(m); m.close()"\n'
warn "Logic 2 must be RUNNING with the automation server enabled for that to work."
say "Done. Activate with:  source $VENV/bin/activate"
