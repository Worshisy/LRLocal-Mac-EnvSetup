#!/usr/bin/env bash
# 50-sourcemeter-venv.sh — direct (non-conda) Python venv for SCAN_sourcemeter.
#
# SCAN_sourcemeter sweeps I-V on a Keithley 2401 SMU over a USB-GPIB adapter
# (VISA resource like GPIB1::24::INSTR) using PyVISA, and plots with
# numpy/pandas/matplotlib in SweepPV.ipynb.
#
# Python side is installed here. The GPIB BACKEND is NOT scriptable:
#   * GPIB over a USB-GPIB adapter needs NI-VISA + NI-488.2 (or the adapter
#     vendor's macOS driver). Install that by hand — see RUNBOOK "manual
#     prerequisites". We install pyvisa-py too as a pure-Python fallback (good
#     for USB-TMC / TCPIP / serial instruments; GPIB on macOS still needs the
#     vendor driver).
set -u

VENV="$HOME/venvs/sourcemeter"

say()  { printf '\n\033[1;36m[50] %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }

say "Creating venv at $VENV"
mkdir -p "$(dirname "$VENV")"
[ -d "$VENV" ] || python3 -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"
python3 -m pip install --upgrade pip >/dev/null
python3 -m pip install pyvisa pyvisa-py pyusb numpy pandas matplotlib jupyter
ok "Installed pyvisa + pyvisa-py + sci stack into $VENV"

say "Verifying"
python3 - <<'PY' && ok "pyvisa imports OK" || warn "pyvisa import failed"
import pyvisa, numpy, pandas
print("  pyvisa", pyvisa.__version__, "| numpy", numpy.__version__, "| pandas", pandas.__version__)
try:
    rm = pyvisa.ResourceManager('@py')      # pure-Python backend
    print("  pyvisa-py backend OK; resources:", rm.list_resources())
except Exception as e:
    print("  pyvisa-py backend note:", e)
PY

warn "GPIB (Keithley 2401 @ GPIB1::24::INSTR) needs a VISA driver for the"
warn "USB-GPIB adapter — install NI-VISA + NI-488.2 (or the adapter vendor's"
warn "macOS driver) by hand. Then list instruments with the DEFAULT backend:"
printf '    source %s/bin/activate\n' "$VENV"
printf '    python3 -c "import pyvisa; print(pyvisa.ResourceManager().list_resources())"\n'
warn "You should see your GPIB instrument (e.g. GPIB1::24::INSTR)."
say "Done. Activate with:  source $VENV/bin/activate"
