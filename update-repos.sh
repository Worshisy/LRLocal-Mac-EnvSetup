#!/usr/bin/env bash
# update-repos.sh — git pull this kit + the 4 project repos on this Mac (mini).
#
# Pulls go through the reverse SOCKS tunnel at localhost:1080 that rides along
# on every operator `ssh ddh-mac-0X` connection (see FIELD-RUNBOOK.md §4) — the
# per-invocation proxy flag persists nothing, so plain git keeps behaving as
# before. Pulls are --ff-only: a repo with local commits/changes is never
# merged or rebased — it's reported and left for you to resolve.
#
# Usage (on the mini, inside an operator SSH session):
#   ./update-repos.sh                     # update all (kit pulls itself last)
#   REPO_BASE=/path ./update-repos.sh     # override repo autodetect
#   WITH_SUBMODULES=1 ./update-repos.sh   # also update USRP uhd+gnuradio submodules (GBs)
#   PROXY=socks5h://127.0.0.1:1081 ./update-repos.sh   # different tunnel port
set -u

say()  { printf '\n\033[1;36m[update] %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS=(FT232_SCAN_IO LRLocal-V2 USRP_study_yishen RTK_dev_for_cm-loc)
TUNNEL=socks5h://127.0.0.1:1080

# same lookup as field-jobs.sh: kit's parent dir, then ~/Projects, then ~
find_dir() {  # $1 = repo name
  for b in "${REPO_BASE:-}" "$(cd "$HERE/.." && pwd)" "$HOME/Projects" "$HOME"; do
    [ -n "$b" ] && [ -d "$b/$1" ] && { echo "$b/$1"; return 0; }
  done
  return 1
}

# [c] Always pull through the operator's reverse SOCKS tunnel (the new ssh
# way) — per-invocation `-c http.proxy` only, so the repos' normal git config
# and direct-internet behavior stay untouched. PROXY_OPTS is a plain string
# (bash 3.2 + set -u chokes on empty arrays); expanded UNQUOTED — the URL has
# no spaces.
PROXY_OPTS=""
pick_route() {
  local url="${PROXY:-$TUNNEL}"
  if curl -fsS -m 5 -x "$url" https://github.com >/dev/null 2>&1; then
    PROXY_OPTS="-c http.proxy=$url"
    ok "pulling via the reverse SOCKS tunnel ($url)"; return
  fi
  warn "github.com unreachable via $url — the tunnel isn't up."
  warn "Connect from the operator with  ssh ddh-mac-0X  (carries the tunnel), then re-run."
  exit 1
}

update_one() {  # $1 = repo dir
  local dir="$1" name out rc before after dirty=""
  name="$(basename "$dir")"
  [ -d "$dir/.git" ] || { warn "$name: no .git here ($dir) — skipping"; return; }
  [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ] && dirty="  (local changes present — untouched)"
  before="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)"
  # shellcheck disable=SC2086  # PROXY_OPTS intentionally word-split
  out="$(git -C "$dir" $PROXY_OPTS pull --ff-only 2>&1)"; rc=$?
  if [ $rc -ne 0 ]; then
    warn "$name: pull FAILED (diverged / conflict / auth?) — resolve manually:"
    printf '%s\n' "$out" | sed 's/^/      /'
    return 1
  fi
  after="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)"
  if [ "$before" = "$after" ]; then ok "$name: already up to date$dirty"
  else ok "$name: $before → $after$dirty"; fi
  if [ "$name" = "USRP_study_yishen" ] && [ "${WITH_SUBMODULES:-0}" = "1" ]; then
    say "USRP submodules (uhd + gnuradio — several GB on first pull)"
    # shellcheck disable=SC2086
    git -C "$dir" $PROXY_OPTS submodule update --init --recursive \
      && ok "submodules updated" || warn "submodule update failed"
  fi
}

# main() wrapper: bash parses the whole file before running it, so the kit's
# self-pull at the end can't corrupt this script mid-execution.
main() {
  say "Updating repos (ff-only)"
  pick_route
  local r dir nfail=0
  for r in "${REPOS[@]}"; do
    if dir="$(find_dir "$r")"; then update_one "$dir" || nfail=$((nfail+1))
    else warn "$r: not found (kit parent / ~/Projects / ~ — set REPO_BASE)"; fi
  done
  say "Updating the kit itself (last — it may replace this script)"
  update_one "$HERE" || nfail=$((nfail+1))
  if [ $nfail -gt 0 ]; then say "Done — $nfail repo(s) FAILED (see above)."; exit 1; fi
  say "Done."
}
main "$@"
