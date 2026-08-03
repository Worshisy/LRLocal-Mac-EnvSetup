#!/usr/bin/env python3
# field-001-psd-web.py — serve the NEWEST RX PSD image as an auto-refreshing
# browser page. Sub-function of field-000-jobs.sh (job "psd"); from the laptop
# open http://192.168.2.1:8081 . New PSDs appear as the capture rotates files.
import argparse
import glob
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

def newest_png(root):
    files = glob.glob(os.path.join(root, "*", "psd", "*.png"))
    return max(files, key=os.path.getmtime) if files else None

PAGE = b"""<!doctype html><title>RX PSD (newest)</title>
<body style="background:#111;color:#ddd;font-family:monospace;text-align:center;margin:8px">
<div id=n style="margin:6px">loading&hellip;</div><img id=i style="max-width:100%">
<script>
async function r(){
  const j = await (await fetch('/info')).json();
  document.getElementById('n').textContent = j.name ? (j.dir+'/'+j.name+'   ('+j.age+' s old)') : 'no PSD images yet';
  if (j.name) document.getElementById('i').src = '/latest.png?t=' + j.mtime;
}
r(); setInterval(r, 5000);
</script>"""

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):  # keep the tmux log quiet
        pass
    def _send(self, ctype, body):
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        import time
        f = newest_png(self.server.psd_root)
        if self.path.startswith("/latest.png"):
            if not f:
                self.send_error(404, "no PSD yet")
                return
            with open(f, "rb") as fh:
                self._send("image/png", fh.read())
        elif self.path.startswith("/info"):
            mt = os.path.getmtime(f) if f else 0
            body = json.dumps({
                "name": os.path.basename(f) if f else None,
                "dir": os.path.basename(os.path.dirname(os.path.dirname(f))) if f else None,
                "mtime": mt,
                "age": int(time.time() - mt) if f else 0,
            }).encode()
            self._send("application/json", body)
        else:
            self._send("text/html", PAGE)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True, help="capture data root (contains <UTC>/psd/*.png)")
    ap.add_argument("--port", type=int, default=8081)
    args = ap.parse_args()
    srv = HTTPServer(("0.0.0.0", args.port), Handler)
    srv.psd_root = args.root
    print(f"[psd-web] serving newest PSD from {args.root} on http://0.0.0.0:{args.port}", flush=True)
    srv.serve_forever()

if __name__ == "__main__":
    main()
