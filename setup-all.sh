#!/usr/bin/env bash
# setup-all.sh — run the whole Mac-mini environment setup in order.
#
# Order matters: 00 (brew + libusb) must precede 20 (FT232 needs libusb).
# Each step is idempotent; re-run any step alone if one fails.
#
# Usage:
#   ./setup-all.sh              # run all steps, pausing before each
#   ./setup-all.sh -y           # run all steps without pausing
#   ./setup-all.sh 00 10        # run only the named steps
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

AUTO=0
STEPS=()
for a in "$@"; do
  case "$a" in
    -y|--yes) AUTO=1 ;;
    *) STEPS+=("$a") ;;
  esac
done
[ ${#STEPS[@]} -eq 0 ] && STEPS=(00 10 20 30 50 60 70 40)

declare -A SCRIPT=(
  [00]=00-base-tools.sh
  [10]=10-usrp-conda-env.sh
  [20]=20-ft232-venv.sh
  [30]=30-rtk-venv.sh
  [50]=50-sourcemeter-venv.sh
  [60]=60-saleae-venv.sh
  [70]=70-gr-filerepeater.sh
  [40]=40-ssh-remote.sh
)
declare -A DESC=(
  [00]="Base tools: Xcode CLT, Homebrew, libusb"
  [10]="Miniconda + single 'usrp' env (UHD/GNU Radio/GRC + LRLocal-V2 Python)"
  [20]="FT232_SCAN_IO venv (pyftdi)"
  [30]="RTK venv (pyserial)"
  [50]="SCAN_sourcemeter venv (pyvisa) — Keithley SMU"
  [60]="Saleae venv (logic2-automation) — Logic analyzer"
  [70]="gr-filerepeater OOT module (build into usrp env) — GRC flowgraph blocks"
  [40]="Remote access: SSH + Screen Sharing"
)

printf '\n\033[1;35m== Mac-mini environment setup ==\033[0m\n'
printf 'Target: Apple-Silicon macOS. Steps to run: %s\n' "${STEPS[*]}"

for s in "${STEPS[@]}"; do
  scr="${SCRIPT[$s]:-}"
  [ -z "$scr" ] && { printf '\033[1;33mUnknown step "%s" — skipping.\033[0m\n' "$s"; continue; }
  printf '\n\033[1;35m──────── Step %s: %s ────────\033[0m\n' "$s" "${DESC[$s]}"
  if [ "$AUTO" -ne 1 ]; then
    read -r -p "Run step $s? [Y/n/q] " ans
    case "$ans" in
      [Nn]*) echo "skipped."; continue ;;
      [Qq]*) echo "quit."; exit 0 ;;
    esac
  fi
  bash "$HERE/$scr" || { printf '\033[1;31mStep %s failed. Fix and re-run: ./%s\033[0m\n' "$s" "$scr"; exit 1; }
done

printf '\n\033[1;32m== All requested steps complete. ==\033[0m\n'
printf 'See README.md for per-repo run instructions and the MATLAB/Vivado manual prereqs.\n'
