#!/usr/bin/env bash
# host-000-ssh-config.sh — set up the OPERATOR machine (your laptop / lab Mac) to
# reach the field minis with short names. RUN THIS ON THE HOST, not on a mini.
#
#   ssh ddh-mac-03      →  ddh-macmini4-03@192.168.2.1 (unit 03's AP), plus:
#     * RemoteForward 1080 — reverse SOCKS proxy: the offline mini can reach
#       the internet THROUGH this machine (on the mini: `gitp pull` / `proxyon`,
#       installed by step 040 of the kit).
#     * host-key nagging off for 192.168.2.1 — every mini reuses that IP with
#       its own host key, so the "REMOTE HOST IDENTIFICATION HAS CHANGED"
#       warning is expected and safe to suppress here.
#
# Idempotent: rewrites its own managed block in ~/.ssh/config on re-run; the
# rest of your config is left untouched.
set -u

say()  { printf '\n\033[1;36m[host-ssh] %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }

CFG="$HOME/.ssh/config"
MARK_BEGIN='# >>> LRLocal field minis (managed by LRLocal-Mac-EnvSetup/host-000-ssh-config.sh) >>>'
# [c] strip by the STABLE prefix, so blocks written under any older script name
# (host-ssh-config.sh, host-010-…) are replaced, never duplicated
MARK_PREFIX='# >>> LRLocal field minis'
MARK_END='# <<< LRLocal field minis <<<'

say "Installing ddh-mac-0X shortcuts into $CFG"
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
touch "$CFG"

# drop any previous managed block (portable awk — BSD/GNU sed -i differ)
TMP="$(mktemp)"
awk -v b="$MARK_PREFIX" -v e="$MARK_END" \
    'index($0,b)==1{skip=1} skip==0{print} index($0,e)==1{skip=0}' "$CFG" > "$TMP"
mv "$TMP" "$CFG"

cat >> "$CFG" <<EOF
$MARK_BEGIN
# ssh ddh-mac-0X → ddh-macmini4-0X@192.168.2.1 (join that unit's AP first).
# RemoteForward 1080 = reverse SOCKS so the offline mini can git pull /
# install through THIS machine's internet (on the mini: gitp / proxyon).
Host ddh-mac-01
    User ddh-macmini4-01
Host ddh-mac-02
    User ddh-macmini4-02
Host ddh-mac-03
    User ddh-macmini4-03
Host ddh-mac-04
    User ddh-macmini4-04
Host ddh-mac-05
    User ddh-macmini4-05
Host ddh-mac-06
    User ddh-macmini4-06

# TX Raspberry Pi (AP ddh-pi4-beacon, own subnet .3.1 — see pi-000-hotspot.sh)
Host ddh-pi4-beacon
    HostName 192.168.3.1
    User user
    # [c] push this PC's clock to the Pi on every connection (no NTP off-grid;
    # covers the no-internet case — the Pi-side tunnel sync handles the rest).
    # Gated at >=2 s drift; inner ssh disables LocalCommand to avoid recursion.
    PermitLocalCommand yes
    LocalCommand /bin/sh -c 'e=\$(( \$(date +%%s) + 1 )); ssh -o PermitLocalCommand=no -o ClearAllForwardings=yes ddh-pi4-beacon "d=\\\$(( \\\$(date +%%s) - \$e )); [ \\\${d#-} -ge 2 ] && sudo -n date -us @\$e" >/dev/null 2>&1 &'

Host ddh-mac-0* ddh-pi4-beacon 192.168.2.1 192.168.3.1
    RemoteForward 1080
    # every field unit reuses its AP IP with its own host key — don't warn/abort
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host ddh-mac-0* 192.168.2.1
    HostName 192.168.2.1
$MARK_END
EOF
chmod 600 "$CFG"
ok "managed block written (shortcuts ddh-mac-01 … ddh-mac-06)"
ok "try:  ssh ddh-mac-01     (after joining that mini's macmini-field-01 Wi-Fi)"
say "Done."
