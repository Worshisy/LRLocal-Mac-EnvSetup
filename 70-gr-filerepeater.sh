#!/usr/bin/env bash
# 70-gr-filerepeater.sh — build the gr-filerepeater OOT module into the usrp env.
#
# The USRP_study_yishen GRC flowgraphs (grc/B200_FileRec.grc, B200_SpecAna.grc)
# use blocks from the out-of-tree module gr-filerepeater (ghostop14):
#   filerepeater_AdvFileSink, filerepeater_StateOr, filerepeater_StateTimer
# Without it, GRC shows "Missing Block". It's a C++/pybind11 OOT module (targets
# GNU Radio 3.9+), so it must be COMPILED against the GR 3.10 in the usrp env and
# installed into $CONDA_PREFIX. Not on conda-forge/pip.
#
# Source: https://github.com/ghostop14/gr-filerepeater  (last commit 2023-09)
set -u

SRC="$HOME/src/gr-filerepeater"
REPO="https://github.com/ghostop14/gr-filerepeater.git"

say()  { printf '\n\033[1;36m[70] %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }

# ── 1. usrp conda env (provides GR 3.10 + cmake + compilers + boost) ──────────
say "Activating the usrp conda env"
CONDA_SH=""
for d in "$HOME/miniconda3" "$HOME/miniforge3" "$HOME/anaconda3"; do
  [ -f "$d/etc/profile.d/conda.sh" ] && CONDA_SH="$d/etc/profile.d/conda.sh" && break
done
[ -z "$CONDA_SH" ] && { warn "conda not found — run ./10-usrp-conda-env.sh first"; exit 1; }
# shellcheck disable=SC1090
source "$CONDA_SH"; set +u; conda activate usrp; set -u
ok "CONDA_PREFIX=$CONDA_PREFIX"
command -v gnuradio-config-info >/dev/null 2>&1 && ok "GNU Radio $(gnuradio-config-info --version 2>/dev/null)" || { warn "GNU Radio not in env"; exit 1; }
# pybind11 is needed to build the bindings; ensure it's present.
# (conda's shell function isn't set -u safe, so relax it for the install.)
if ! python -c "import pybind11" 2>/dev/null; then
  warn "installing pybind11 into env"
  set +u; conda install -y -n usrp pybind11 >/dev/null 2>&1 || true; set -u
fi

# ── 2. Clone / update source ──────────────────────────────────────────────────
say "Fetching gr-filerepeater source -> $SRC"
mkdir -p "$(dirname "$SRC")"
if [ -d "$SRC/.git" ]; then git -C "$SRC" pull --ff-only || true; else git clone "$REPO" "$SRC" || { warn "clone failed"; exit 1; }; fi

# ── 3. Build + install into $CONDA_PREFIX ─────────────────────────────────────
say "Building (into \$CONDA_PREFIX so GRC/GNU Radio find the blocks)"
cd "$SRC" && rm -rf build && mkdir build && cd build
cmake -DCMAKE_INSTALL_PREFIX="$CONDA_PREFIX" -DCMAKE_PREFIX_PATH="$CONDA_PREFIX" .. \
  || { warn "cmake configure failed (check GR version / pybind11)"; exit 1; }
make -j"$(sysctl -n hw.ncpu)" || { warn "build failed"; exit 1; }
make install || { warn "install failed"; exit 1; }
# refresh the linker/python caches for the env
[ -d "$CONDA_PREFIX/share/gnuradio/grc/blocks" ] && ok "GRC block defs installed"

# ── 4. Verify ─────────────────────────────────────────────────────────────────
say "Verifying"
ls "$CONDA_PREFIX"/share/gnuradio/grc/blocks/filerepeater_*.block.yml 2>/dev/null | head && ok "GRC sees filerepeater_* blocks" || warn "no filerepeater .block.yml found"
python - <<'PY' 2>/dev/null && ok "python import OK" || warn "python import note (may still work in GRC)"
import filerepeater
print("  filerepeater module:", filerepeater.__file__)
PY
say "Done. Restart gnuradio-companion (grc) — the 'Missing Block' errors should be gone."
