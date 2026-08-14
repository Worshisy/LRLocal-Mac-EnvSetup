#!/usr/bin/env python3
# [c] Build the GPS<->host time LINK FILE from a session's relposned_*.csv.
# The rtk monitor already stamps every RELPOSNED row with host_time (arrival)
# and iTOW (GPS time-of-week folded to time-of-day by itow_label) — this tool
# just derives (host_epoch, gps_utc, offset_ms) rows plus a drift-line fit, so
# any rx sample maps to GPS time:
#     gps_utc = host_time_of_sample - offset(host_time)      [ms accuracy]
# The rx chain is never touched; run this any time during or after a session.
#
#   rtk-011-make-gps-link.py --csv <relposned_*.csv> [--out gps_host_link.csv]
#   rtk-011-make-gps-link.py --session <data/UTC dir>     (newest csv inside)
#
# iTOW is on the GPS timescale: GPS = UTC + GPS_UTC_LEAP_S. host_time is local
# time from datetime.now() — converted to UTC via the host's own zone offset.
import argparse
import glob
import os
import sys
from datetime import datetime, timedelta, timezone

GPS_UTC_LEAP_S = 18            # GPS - UTC leap seconds (constant since 2017)

ap = argparse.ArgumentParser()
ap.add_argument("--csv")
ap.add_argument("--session")
ap.add_argument("--out")
args = ap.parse_args()

csv_path = args.csv
if not csv_path and args.session:
    cands = sorted(glob.glob(os.path.join(args.session, "relposned_*.csv")))
    csv_path = cands[-1] if cands else None
if not csv_path or not os.path.exists(csv_path):
    sys.exit("no relposned csv found (use --csv or --session)")
out_path = args.out or os.path.join(os.path.dirname(csv_path), "gps_host_link.csv")

rows = []
with open(csv_path) as f:
    for ln in f:
        p = ln.strip().split(",")
        if len(p) < 7 or p[0] == "host_time":
            continue
        try:
            host_local = datetime.fromisoformat(p[0])       # naive local time
            hh, mm, sec = p[1].split(":")
            gps_tod = int(hh) * 3600 + int(mm) * 60 + float(sec)
        except ValueError:
            continue
        host_utc = host_local.astimezone(timezone.utc) if host_local.tzinfo \
            else host_local.replace(tzinfo=datetime.now().astimezone().tzinfo).astimezone(timezone.utc)
        # resolve the GPS time-of-day onto the host's UTC date (nearest day)
        day0 = host_utc.replace(hour=0, minute=0, second=0, microsecond=0)
        best = min((day0 + timedelta(days=d, seconds=gps_tod) for d in (-1, 0, 1)),
                   key=lambda t: abs((t - host_utc).total_seconds()))
        gps_utc = best - timedelta(seconds=GPS_UTC_LEAP_S)
        offset_ms = (host_utc - gps_utc).total_seconds() * 1e3
        rows.append((host_utc.timestamp(), host_utc.isoformat(),
                     gps_utc.isoformat(), offset_ms, p[6]))

if not rows:
    sys.exit(f"no parseable rows in {csv_path}")

# straight-line fit offset(t): measures the host oscillator drift (ppm)
t0 = rows[0][0]
xs = [r[0] - t0 for r in rows]
ys = [r[3] for r in rows]
n = len(xs)
mx, my = sum(xs) / n, sum(ys) / n
den = sum((x - mx) ** 2 for x in xs) or 1.0
slope = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / den   # ms/s
intercept = my - slope * mx
med = sorted(ys)[n // 2]

with open(out_path, "w") as out:
    out.write(f"# source: {os.path.basename(csv_path)}  rows: {n}\n")
    out.write(f"# offset_ms = host_utc - gps_utc (positive = host ahead); "
              f"GPS-UTC leap {GPS_UTC_LEAP_S} s already removed\n")
    out.write(f"# median_offset_ms {med:.1f}  fit: offset_ms(t) = {intercept:.2f} "
              f"+ {slope:.6f}*(host_epoch-{t0:.3f})  [drift {slope*1e3:.2f} ppm]\n")
    out.write("host_epoch_s,host_utc_iso,gps_utc_iso,offset_ms,carrSoln\n")
    for r in rows:
        out.write(f"{r[0]:.3f},{r[1]},{r[2]},{r[3]:.1f},{r[4]}\n")

print(f"link file: {out_path}")
print(f"rows {n}  span {xs[-1]:.0f}s  median offset {med:.1f} ms  "
      f"drift {slope*1e3:.2f} ppm  scatter p5..p95 "
      f"{sorted(ys)[max(0,n//20)]:.1f}..{sorted(ys)[min(n-1,n-1-n//20)]:.1f} ms")
