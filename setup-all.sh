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
[ ${#STEPS[@]} -eq 0 ] && STEPS=(00 10 70 40 80)

# NOTE: no `declare -A` here — macOS ships bash 3.2 (no associative arrays).
# Use case-based lookups so this runs on the stock /bin/bash of a fresh Mac.
script_for() {
  case "$1" in
    00) echo 00-base-tools.sh ;;
    10) echo 10-usrp-conda-env.sh ;;
    70) echo 70-gr-filerepeater.sh ;;
    40) echo 40-ssh-remote.sh ;;
    80) echo 80-hotspot.sh ;;
  esac
}
desc_for() {
  case "$1" in
    00) echo "Base tools: Xcode CLT, Homebrew, libusb (optional — conda has its own)" ;;
    10) echo "Miniconda + single 'usrp' env — ALL tools (USRP/GRC, LRLocal-V2 Py, FT232, RTK, Saleae)" ;;
    70) echo "gr-filerepeater OOT module (build into usrp env) — GRC flowgraph blocks" ;;
    40) echo "Remote access: SSH + Screen Sharing" ;;
    80) echo "Wi-Fi hotspot (macOS Internet Sharing)" ;;
  esac
}

printf '\n\033[1;35m== Mac-mini environment setup ==\033[0m\n'
printf 'Target: Apple-Silicon macOS. Steps to run: %s\n' "${STEPS[*]}"

for s in "${STEPS[@]}"; do
  scr="$(script_for "$s")"
  [ -z "$scr" ] && { printf '\033[1;33mUnknown step "%s" — skipping.\033[0m\n' "$s"; continue; }
  printf '\n\033[1;35m──────── Step %s: %s ────────\033[0m\n' "$s" "$(desc_for "$s")"
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
