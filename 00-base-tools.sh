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

# Run as your NORMAL user, NOT sudo — Homebrew refuses to install as root and
# calls sudo itself only where needed.
if [ "$(id -u)" -eq 0 ]; then
  warn "Don't run this with sudo. Run it as your normal user:  ./00-base-tools.sh"
  exit 1
fi

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
  # Homebrew install needs admin/sudo. On a NON-admin account it can't install —
  # and that's OK: Homebrew is optional for these projects (FT232 falls back to a
  # pip-bundled libusb in step 20). So skip gracefully instead of failing.
  IS_ADMIN=no
  case " $(id -Gn 2>/dev/null) " in *" admin "*) IS_ADMIN=yes ;; esac
  if [ "$IS_ADMIN" != yes ]; then
    warn "User '$(whoami)' is NOT an admin → skipping Homebrew (it needs sudo)."
    warn "That's fine: FT232 (step 20) uses a pip libusb backend; conda has its own."
    warn "If you want Homebrew, have an admin install it, or make this user an admin."
    say "Done (Homebrew skipped). Versions:"; ok "$(git --version)"
    exit 0
  fi
  # IMPORTANT: Homebrew's NONINTERACTIVE mode does NOT prompt for sudo itself —
  # it requires sudo credentials to be ALREADY cached, else it fails with a
  # misleading "needs to be an Administrator" message (even for admins). So we
  # pre-authorize sudo here (one password prompt), THEN run the installer.
  warn "Installing Homebrew — enter your login password at the sudo prompt…"
  if ! sudo -v; then
    warn "Couldn't get sudo (wrong password, or not an admin). Homebrew is optional"
    warn "(FT232 uses the pip libusb fallback) — skipping. Re-run as an admin to add it."
    say "Done (Homebrew skipped)."; ok "$(git --version)"
    exit 0
  fi
  if ! NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
    warn "Homebrew install failed (network?). It's optional (FT232 uses the pip libusb fallback)."
    warn "Fix and re-run if you want it; continuing without it."
    say "Done (Homebrew not installed)."; ok "$(git --version)"
    exit 0
  fi
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
