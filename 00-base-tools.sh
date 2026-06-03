#!/usr/bin/env bash
# 00-base-tools.sh — base prerequisites shared by everything else.
#   * Xcode Command Line Tools (git, clang, make)
#   * Homebrew (package manager)
#   * libusb (USB backend pyftdi needs for the FT232H, step 20)
#
# Idempotent: safe to re-run. Homebrew install needs network + your sudo
# password (it asks once). Everything here targets Apple-Silicon macOS.
set -u

say()  { printf '\n\033[1;36m[00] %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }

# ── 1. Xcode Command Line Tools ───────────────────────────────────────────────
say "Checking Xcode Command Line Tools"
if xcode-select -p >/dev/null 2>&1; then
  ok "Command Line Tools present at $(xcode-select -p)"
else
  warn "Not found — launching the installer GUI. Finish it, then re-run this script."
  xcode-select --install || true
  exit 1
fi

# ── 2. Homebrew ───────────────────────────────────────────────────────────────
say "Checking Homebrew"
BREW=""
for c in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  [ -x "$c" ] && BREW="$c" && break
done
if [ -z "$BREW" ] && command -v brew >/dev/null 2>&1; then BREW="$(command -v brew)"; fi

if [ -n "$BREW" ]; then
  ok "Homebrew already installed ($BREW)"
else
  warn "Installing Homebrew (will prompt for your sudo password once)…"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
      warn "Homebrew install failed. Re-run after fixing network/sudo."; exit 1; }
  BREW="/opt/homebrew/bin/brew"
fi

# Make brew usable in THIS shell, and persist for future shells.
eval "$("$BREW" shellenv)"
if ! grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null; then
  # shellcheck disable=SC2016
  echo 'eval "$('"$BREW"' shellenv)"' >> "$HOME/.zprofile"
  ok "Added brew shellenv to ~/.zprofile"
fi

# ── 3. libusb (FT232H backend) ────────────────────────────────────────────────
say "Installing libusb (USB backend for pyftdi / FT232H)"
if brew list libusb >/dev/null 2>&1; then
  ok "libusb already installed"
else
  brew install libusb && ok "libusb installed"
fi

say "Done. Versions:"
ok "$(git --version)"
ok "$(brew --version | head -1)"
ok "libusb: $(brew --prefix libusb 2>/dev/null)"
