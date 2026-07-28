#!/usr/bin/env bash
# setup-000-all.sh — run the whole Mac-mini environment setup in order.
#
# Script naming: <setup|field|host>-XXX-<name>.sh, XXX = 0<step><sub>
# (sub 0 = the step's main script, 1-9 = sub-functions of that step).
# Each step is idempotent; re-run any step alone if one fails.
#
# Usage:
#   ./setup-000-all.sh              # run all steps, pausing before each
#   ./setup-000-all.sh -y           # run all steps without pausing
#   ./setup-000-all.sh 010 020      # run only the named steps
#                                   # (legacy ids 00/10/40/70/80 still accepted)
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
[ ${#STEPS[@]} -eq 0 ] && STEPS=(010 020 030 040 050 060)

# NOTE: no `declare -A` here — macOS ships bash 3.2 (no associative arrays).
# Use case-based lookups so this runs on the stock /bin/bash of a fresh Mac.
# [c] legacy 2-digit ids (pre-2026-07-28 naming) map to the new steps.
script_for() {
  case "$1" in
    010|00) echo setup-010-base-tools.sh ;;
    020|10) echo setup-020-usrp-conda-env.sh ;;
    030)    echo setup-030-clone-repos.sh ;;
    040|40) echo setup-040-ssh-remote.sh ;;
    050|70) echo setup-050-gr-filerepeater.sh ;;
    060|80) echo setup-060-hotspot.sh ;;
  esac
}
desc_for() {
  case "$1" in
    010|00) echo "Base tools: Xcode CLT, Homebrew, libusb (optional — conda has its own)" ;;
    020|10) echo "Miniconda + single 'usrp' env — ALL tools (USRP/GRC, LRLocal-V2 Py, FT232, RTK, Saleae)" ;;
    030)    echo "Clone the 4 project repos + rx-data symlink (asks GitHub auth if not logged in)" ;;
    040|40) echo "Remote access: SSH + Screen Sharing + reverse-SOCKS proxy helpers" ;;
    050|70) echo "gr-filerepeater OOT module (build into usrp env) — GRC flowgraph blocks" ;;
    060|80) echo "Wi-Fi hotspot (macOS Internet Sharing)" ;;
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
