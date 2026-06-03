#!/usr/bin/env bash
# 30-rtk-venv.sh — direct (non-conda) Python venv for RTK_dev_for_cm-loc.
#
# The RELPOSNED monitor only needs pyserial (requirements.txt: pyserial>=3.5).
# Per Yi's instruction RTK is installed directly, not in the conda env.
set -u

VENV="$HOME/venvs/rtk"

say()  { printf '\n\033[1;36m[30] %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }

say "Creating venv at $VENV"
mkdir -p "$(dirname "$VENV")"
[ -d "$VENV" ] || python3 -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"
python3 -m pip install --upgrade pip >/dev/null
python3 -m pip install 'pyserial>=3.5'
ok "Installed pyserial into $VENV"

say "Verifying"
python3 - <<'PY' && ok "pyserial imports OK" || warn "pyserial import failed"
import serial
print("  pyserial", serial.__version__)
PY
warn "Connect the rover board over USB, then run (from the RTK repo):"
printf '    source %s/bin/activate\n' "$VENV"
printf '    python3 relposned_monitor.py --mode web --port /dev/cu.usbmodemXXXXXX\n'
warn "Find the port with:  ls /dev/cu.usbmodem*"
say "Done. Activate with:  source $VENV/bin/activate"
