#!/bin/bash
###############################################################################
# export_result.sh — expense_fraud_investigation
# Collects task artifacts into /tmp/task_result.json for the verifier.
###############################################################################

# ── 1. Record end timestamp ──────────────────────────────────────────────
rm -f /tmp/task_end_time.txt
date +%s > /tmp/task_end_time.txt

# ── 2. Final screenshot ──────────────────────────────────────────────────
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# ── 3. Kill HTTP server ──────────────────────────────────────────────────
pkill -f "http.server 8080" 2>/dev/null || true

# ── 4. Graceful Chrome shutdown (flush JSON files to disk) ───────────────
pkill -15 -f "google-chrome" 2>/dev/null || true
sleep 4
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# ── 5. Collect everything in one Python script (avoids bash/python nesting) ─
python3 << 'PYEOF'
import json, os, time

task_start = 0
try:
    with open("/tmp/task_start_time.txt") as f:
        task_start = int(f.read().strip())
except Exception:
    pass

task_end = int(time.time())

# ── Report file ──
report_path = "/home/ga/Documents/Fraud_Investigation/report.txt"
report = {"exists": False, "size": 0, "created_during_task": False, "content": ""}
if os.path.isfile(report_path):
    report["exists"] = True
    report["size"] = os.path.getsize(report_path)
    mtime = int(os.path.getmtime(report_path))
    report["created_during_task"] = mtime >= task_start
    try:
        with open(report_path, "r", errors="replace") as f:
            report["content"] = f.read()
    except Exception:
        pass

# ── Chrome bookmarks ──
bookmarks_raw = {}
for bpath in ["/home/ga/.config/google-chrome-cdp/Default/Bookmarks",
              "/home/ga/.config/google-chrome/Default/Bookmarks"]:
    if os.path.isfile(bpath):
        try:
            with open(bpath) as f:
                bookmarks_raw = json.load(f)
        except Exception:
            pass
        break

# ── Chrome download directory ──
download_dir = ""
for ppath in ["/home/ga/.config/google-chrome-cdp/Default/Preferences",
              "/home/ga/.config/google-chrome/Default/Preferences"]:
    if os.path.isfile(ppath):
        try:
            with open(ppath) as f:
                prefs = json.load(f)
            download_dir = prefs.get("download", {}).get("default_directory", "")
        except Exception:
            pass
        break

# ── Write result ──
result = {
    "task_start": task_start,
    "task_end": task_end,
    "report": report,
    "bookmarks_raw": bookmarks_raw,
    "download_dir": download_dir,
}

out_path = "/tmp/task_result.json"
with open(out_path, "w") as f:
    json.dump(result, f, indent=2)
os.chmod(out_path, 0o666)
print("Result written to " + out_path)
PYEOF

echo "=== expense_fraud_investigation export complete ==="
