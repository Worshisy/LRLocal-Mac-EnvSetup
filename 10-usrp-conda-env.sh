#!/usr/bin/env bash
# 10-usrp-conda-env.sh — Miniconda + the single `usrp` env.
#
# Installs Miniconda (Apple-Silicon) if absent, then builds the one conda env
# that covers ALL USRP / GNU Radio (GRC) work AND the LRLocal-V2 Python branch,
# from env/usrp-env.yml. Idempotent: re-running updates the env in place.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_YML="$HERE/env/usrp-env.yml"
ENV_NAME="usrp"
MINICONDA_DIR="$HOME/miniconda3"

say()  { printf '\n\033[1;36m[10] %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }

# ── 1. Locate or install conda ────────────────────────────────────────────────
say "Locating conda"
CONDA_SH=""
for d in "$MINICONDA_DIR" "$HOME/miniforge3" "$HOME/anaconda3" "$HOME/radioconda"; do
  [ -f "$d/etc/profile.d/conda.sh" ] && CONDA_SH="$d/etc/profile.d/conda.sh" && break
done

if [ -z "$CONDA_SH" ]; then
  warn "No conda found — installing Miniconda to $MINICONDA_DIR"
  curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-arm64.sh \
       -o /tmp/miniconda-arm64.sh || { warn "download failed"; exit 1; }
  bash /tmp/miniconda-arm64.sh -b -p "$MINICONDA_DIR" || { warn "install failed"; exit 1; }
  CONDA_SH="$MINICONDA_DIR/etc/profile.d/conda.sh"
  ok "Miniconda installed"
else
  ok "Found conda: $CONDA_SH"
fi

# shellcheck disable=SC1090
source "$CONDA_SH"
# Persist conda for future interactive shells (writes to ~/.zshrc once).
conda init zsh >/dev/null 2>&1 || true

# ── 2. Create or update the env ───────────────────────────────────────────────
say "Building the '$ENV_NAME' env from $ENV_YML"
if conda env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
  warn "Env '$ENV_NAME' exists — updating to match the yml"
  conda env update -n "$ENV_NAME" -f "$ENV_YML" --prune
else
  if ! conda env create -f "$ENV_YML"; then
    warn "Solve failed — likely the uhd=4.9 pin. Retrying with unpinned uhd."
    warn "(conda-forge may not have a gnuradio build against uhd 4.9 on this arch.)"
    sed 's/^\(\s*-\s*\)uhd=4\.9.*/\1uhd/' "$ENV_YML" > /tmp/usrp-env-fallback.yml
    conda env create -f /tmp/usrp-env-fallback.yml || { warn "env create failed"; exit 1; }
  fi
fi

# ── 3. Verify ─────────────────────────────────────────────────────────────────
say "Verifying the env"
conda activate "$ENV_NAME"
ok "CONDA_PREFIX = $CONDA_PREFIX"
command -v uhd_find_devices >/dev/null 2>&1 && ok "uhd_find_devices: $(command -v uhd_find_devices)" || warn "uhd_find_devices missing"
command -v gnuradio-companion >/dev/null 2>&1 && ok "gnuradio-companion present (GRC GUI)" || warn "gnuradio-companion missing"
command -v cmake >/dev/null 2>&1 && ok "$(cmake --version | head -1)" || warn "cmake missing"
python - <<'PY' && ok "python imports OK" || warn "python import check failed"
import uhd, numpy, scipy, matplotlib, pandas, tqdm
print("  uhd", uhd.__version__, "| numpy", numpy.__version__)
try:
    import gnuradio; print("  gnuradio", gnuradio.gr.version())
except Exception as e:
    print("  gnuradio import note:", e)
PY

say "Done. Use it with:  conda activate $ENV_NAME"
warn "USRP C++ host apps (00-/01-/11-/…): activate this env first so its UHD/Boost win, then cmake/make per each project's notes/run-steps-sy.md."
