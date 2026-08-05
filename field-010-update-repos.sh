#!/usr/bin/env bash
# field-010-update-repos.sh — git pull this kit + the project repos on this Mac
# (mini). (FT232_SCAN_IO is deliberately NOT in the list — it doesn't need
# updating on the minis; it's still cloned once by setup-030-clone-repos.sh.)
#
# Pulls go through the reverse SOCKS tunnel at localhost:1080 that rides along
# on every operator `ssh ddh-mac-0X` connection (see FIELD-RUNBOOK.md §4) — the
# per-invocation proxy flag persists nothing, so plain git keeps behaving as
# before. Pulls are --ff-only: a repo with local commits/changes is never
# merged or rebased — it's reported and left for you to resolve.
#
# Usage (on the mini, inside an operator SSH session):
#   ./field-010-update-repos.sh                     # update all (kit pulls itself last)
#   REPO_BASE=/path ./field-010-update-repos.sh     # override repo autodetect
#   WITH_SUBMODULES=1 ./field-010-update-repos.sh   # also update USRP uhd+gnuradio submodules (GBs)
#   PROXY=socks5h://127.0.0.1:1081 ./field-010-update-repos.sh   # different tunnel port
#   OVERWRITE=1 ./field-010-update-repos.sh         # pre-confirm the overwrite prompt (no-tty runs)
set -u

say()  { printf '\n\033[1;36m[update] %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS=(LRLocal-V2 USRP_study_yishen RTK_dev_for_cm-loc)   # [c] FT232_SCAN_IO dropped (Yi, 2026-07-28)
TUNNEL=socks5h://127.0.0.1:1080

# [c] like field-011's lookup: kit parent, then /Volumes/USRP* (repos live on
# the capture SSD on some minis), then ~/Projects, then ~
find_dir() {  # $1 = repo name
  for b in "${REPO_BASE:-}" "$(cd "$HERE/.." && pwd)" /Volumes/USRP* "$HOME/Projects" "$HOME"; do
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

# [c] One y/N confirm before discarding local work. Honoured only on a real
# terminal; OVERWRITE=1 pre-confirms so no-tty runs (agent / `ssh host cmd`)
# can opt in explicitly instead of silently destroying edits.
confirm_overwrite() {  # $1 = repo name
  local a
  [ "${OVERWRITE:-0}" = "1" ] && { warn "OVERWRITE=1 — discarding local changes in $1"; return 0; }
  [ -t 0 ] || { warn "  not a terminal — re-run interactively, or OVERWRITE=1 to discard"; return 1; }
  printf '  overwrite %s with the GitHub version (local changes DISCARDED)? [y/N]: ' "$1"
  read -r a; case "$a" in [yY]*) return 0 ;; *) warn "  not confirmed — left untouched"; return 1 ;; esac
}

# [c] Reset a repo to origin/main. Tracked edits go via reset --hard; untracked
# blockers survive that, so remove exactly the paths git named — never a blanket
# `git clean`, which would eat capture data sitting untracked inside a repo.
overwrite_with_origin() {  # $1 = repo dir, $2 = failed pull output
  local dir="$1" out="$2" p up
  # [c] the tracking ref, not a hardcoded origin/main — not every repo's default
  # branch is main, and a detached/renamed one would silently reset to the wrong tip
  up="$(git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" || up=origin/main
  [ -n "$up" ] || up=origin/main
  git -C "$dir" reset --hard "$up" >/dev/null 2>&1 && return 0
  printf '%s\n' "$out" |
    awk '/would be overwritten by/{f=1;next} /^[A-Za-z]/{f=0} f&&NF{sub(/^[[:space:]]+/,"");print}' |
    while IFS= read -r p; do
      [ -n "$p" ] && [ -e "$dir/$p" ] && rm -rf "$dir/$p" && warn "  removed untracked $p"
    done
  git -C "$dir" reset --hard "$up" >/dev/null 2>&1
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
    # [c] debris from a pull that died mid-checkout (e.g. disk full) shows up
    # as untracked files AND/OR "local changes" blocking the retry. Triage:
    # content identical to origin/main = crash debris; different = real edits.
    if printf '%s' "$out" | grep -qE "untracked working tree files would be overwritten|Your local changes to the following files would be overwritten"; then
      warn "$name: blocked by local files — either real edits made on this Mac,"
      warn "  or leftovers of a pull that died mid-checkout (disk full?). What differs:"
      git -C "$dir" --no-pager diff --stat 2>/dev/null | sed 's/^/      /'
      if confirm_overwrite "$name" && overwrite_with_origin "$dir" "$out"; then
        after="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)"
        ok "$name: $before → $after  (overwritten with the GitHub version)"
        return 0
      fi
      warn "  keep the local work instead:"
      warn "  git -C $dir stash -u && git -C $dir merge --ff-only origin/main && git -C $dir stash pop"
    fi
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
  # [c] show capture-SSD free space — a full disk breaks pulls mid-checkout
  for _v in /Volumes/USRP*; do
    [ -d "$_v" ] && df -h "$_v" | awk -v v="$_v" 'NR==2{printf "  ⛁ %s: %s free of %s (%s used)\n", v, $4, $2, $5}'
  done
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
