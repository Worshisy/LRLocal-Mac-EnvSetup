#!/usr/bin/env bash
# 20-ft232-venv.sh — direct (non-conda) Python venv for FT232_SCAN_IO.
#
# pyftdi drives the FT232H scan chain over libusb (installed in step 00).
# Per Yi's instruction FT232 is installed directly, not in the conda env.
set -u

VENV="$HOME/venvs/ft232"

say()  { printf '\n\033[1;36m[20] %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }

# ── 1. libusb sanity (needs step 00) ──────────────────────────────────────────
say "Checking libusb backend"
if [ -n "$(ls /opt/homebrew/lib/libusb-1.0* /usr/local/lib/libusb-1.0* 2>/dev/null)" ]; then
  ok "libusb present"
else
  warn "libusb not found — run ./00-base-tools.sh first (brew install libusb)."
  exit 1
fi

# ── 2. Create venv + install ──────────────────────────────────────────────────
say "Creating venv at $VENV"
mkdir -p "$(dirname "$VENV")"
[ -d "$VENV" ] || python3 -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"
python3 -m pip install --upgrade pip >/dev/null
python3 -m pip install pyftdi numpy jupyter
ok "Installed pyftdi numpy jupyter into $VENV"

# ── 3. Verify ─────────────────────────────────────────────────────────────────
say "Verifying"
python3 - <<'PY' && ok "pyftdi imports OK" || warn "pyftdi import failed"
import pyftdi, numpy
print("  pyftdi", pyftdi.__version__, "| numpy", numpy.__version__)
PY
warn "Plug in the FT232H, then list it with:"
printf '    source %s/bin/activate\n' "$VENV"
printf '    python3 -c "from pyftdi.ftdi import Ftdi; Ftdi.show_devices()"\n'
warn "Expect a 'ftdi://ftdi:232h:.../1' URL (board enumerates as USB 0x0403:0x6014)."
warn "Do NOT install FTDI's VCP/D2XX driver — it would steal the device from libusb."
say "Done. Activate with:  source $VENV/bin/activate"
