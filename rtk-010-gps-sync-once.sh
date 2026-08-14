#!/bin/bash
# [c] One-shot GPS clock sync for a field mini — run ONCE before starting the
# rtk/rx jobs (the serial port is still free then). Steps the host clock from
# the RTK receiver's NMEA RMC / UBX NAV-PVT stream, then exits; the clock is
# never touched again during the session, so host_time <-> GPS time keeps ONE
# fixed (slowly drifting) relationship for the whole capture. The per-row
# host_time,iTOW pairs in relposned_*.csv are the precise link record
# (rtk-011-make-gps-link.py turns them into gps_host_link.csv).
#
#   rtk-010-gps-sync-once.sh [timeout_s]        (default 20)
#   env: RTK_PORT=/dev/cu.usbmodemXXX  override port autodetect
#
# Exit 0: GPS time observed (clock stepped, or already within 1 s).
# Exit 1: no receiver / no valid fix in time — caller should fall back
#         (field-000-jobs.sh falls back to sync_time_via_tunnel).
# /bin/date sets whole seconds only; the sub-second residual is measured
# continuously by the link file instead — that is by design.
set -u
TIMEOUT="${1:-20}"
PORT="${RTK_PORT:-$(ls /dev/cu.usbmodem* 2>/dev/null | head -1)}"
LOG="$HOME/field-logs/gps_sync_once.log"; mkdir -p "$HOME/field-logs"

note() { echo "[gps-sync] $*"; echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $*" >> "$LOG"; }

[ -z "$PORT" ] && { note "no /dev/cu.usbmodem* device — receiver not plugged in"; exit 1; }

# conda usrp for pyserial (same env the rtk monitor uses). conda's scripts
# use unset vars -> they abort under set -u; relax it around activation.
set +u
source "$HOME/miniconda3/etc/profile.d/conda.sh" 2>/dev/null
conda activate usrp 2>/dev/null
set -u

OUT="$(python - "$PORT" "$TIMEOUT" <<'PYEOF'
# [c] listen for NMEA RMC (UTC date+time, status A) or UBX NAV-PVT (validDate/
# validTime + fullyResolved); print "GPSUTC <iso8601> OFFSET_MS <host-gps ms>".
import struct, sys, time
from datetime import datetime, timezone
import serial

port, timeout_s = sys.argv[1], float(sys.argv[2])
deadline = time.time() + timeout_s

def rmc_utc(line):
    f = line.split(",")
    if len(f) < 10 or f[2] != "A" or len(f[1]) < 6 or len(f[9]) != 6:
        return None
    hh, mm = int(f[1][0:2]), int(f[1][2:4])
    ss = float(f[1][4:])
    dd, mo, yy = int(f[9][0:2]), int(f[9][2:4]), 2000 + int(f[9][4:6])
    return datetime(yy, mo, dd, hh, mm, tzinfo=timezone.utc).timestamp() + ss

def pvt_utc(payload):
    if len(payload) < 92:
        return None
    year, month, day, hour, minute, sec = struct.unpack_from("<HBBBBB", payload, 4)
    valid = payload[11]
    nano = struct.unpack_from("<i", payload, 16)[0]
    if (valid & 0x07) != 0x07:          # validDate|validTime|fullyResolved
        return None
    return (datetime(year, month, day, hour, minute, sec,
                     tzinfo=timezone.utc).timestamp() + nano * 1e-9)

buf = b""
with serial.Serial(port, 38400, timeout=1) as s:
    while time.time() < deadline:
        buf += s.read(4096)
        # NMEA lines
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            t_host = time.time()
            txt = line.decode("ascii", "ignore").strip()
            if len(txt) > 6 and txt[0] == "$" and txt[3:6] == "RMC":
                t_gps = rmc_utc(txt)
                if t_gps:
                    print(f"GPSUTC {datetime.fromtimestamp(t_gps, timezone.utc).isoformat()} "
                          f"OFFSET_MS {round((t_host - t_gps) * 1e3)}")
                    sys.exit(0)
        # UBX NAV-PVT frames in whatever remains
        i = buf.find(b"\xb5\x62\x01\x07")
        if i >= 0 and len(buf) >= i + 6:
            ln = struct.unpack_from("<H", buf, i + 4)[0]
            if len(buf) >= i + 6 + ln + 2:
                t_host = time.time()
                t_gps = pvt_utc(buf[i + 6: i + 6 + ln])
                buf = buf[i + 6 + ln + 2:]
                if t_gps:
                    print(f"GPSUTC {datetime.fromtimestamp(t_gps, timezone.utc).isoformat()} "
                          f"OFFSET_MS {round((t_host - t_gps) * 1e3)}")
                    sys.exit(0)
sys.exit(1)
PYEOF
)"
RC=$?
[ $RC -ne 0 ] && { note "no valid GPS time on $PORT within ${TIMEOUT}s (indoors / no fix?)"; exit 1; }

GPS_ISO="$(echo "$OUT" | awk '{print $2}')"
OFF_MS="$(echo "$OUT" | awk '{print $4}')"
note "GPS UTC $GPS_ISO — host-gps offset ${OFF_MS} ms (port $PORT)"

ABS_MS="${OFF_MS#-}"
if [ "$ABS_MS" -lt 1000 ]; then
    note "clock already within 1 s of GPS — no step (residual is in the link file)"
    exit 0
fi

# step the clock to GPS (whole-second): mirror the sudo pattern of
# sync_time_via_tunnel — passwordless sudo -n first, tty sudo as fallback.
SET_ARG="$(python -c "
from datetime import datetime, timezone
print(datetime.fromisoformat('$GPS_ISO'.replace('Z','+00:00')).strftime('%m%d%H%M%y.%S'))")"
BEFORE="$(date -u '+%H:%M:%S')"
if sudo -n date -u "$SET_ARG" >/dev/null 2>&1 \
   || { [ -t 0 ] && sudo date -u "$SET_ARG" >/dev/null 2>&1; }; then
    note "clock stepped ${OFF_MS} ms: $BEFORE -> $(date -u '+%H:%M:%S') UTC (GPS)"
    exit 0
fi
note "clock is ${OFF_MS} ms off but couldn't set it (sudo needs tty/password)"
exit 1
