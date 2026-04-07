#!/bin/bash
# export_result.sh - Post-task hook for osint_full_page_capture task
# Exports file existence, image dimensions, and browsing history for verification

echo "=== Exporting osint_full_page_capture results ==="

TASK_NAME="osint_full_page_capture"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_final.png 2>/dev/null || true

# Find Tor Browser profile and copy places.sqlite to avoid lock issues
PROFILE_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"
do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done

TEMP_DB="/tmp/${TASK_NAME}_places.sqlite"
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    cp "$PROFILE_DIR/places.sqlite" "$TEMP_DB" 2>/dev/null || true
    [ -f "$PROFILE_DIR/places.sqlite-wal" ] && cp "$PROFILE_DIR/places.sqlite-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "$PROFILE_DIR/places.sqlite-shm" ] && cp "$PROFILE_DIR/places.sqlite-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# Use Python to gather all metrics (Image dimensions, SQLite history, File existence)
cat << 'PYEOF' > /tmp/gather_metrics.py
import json
import os
import sqlite3
import time

try:
    from PIL import Image
except ImportError:
    Image = None

result = {
    "dir_exists": False,
    "full_png_exists": False,
    "full_png_height": 0,
    "full_png_width": 0,
    "full_png_mtime": 0,
    "viewport_png_exists": False,
    "viewport_png_height": 0,
    "viewport_png_width": 0,
    "viewport_png_mtime": 0,
    "log_exists": False,
    "log_content": "",
    "history_community_torproject": False,
    "history_check_torproject": False,
    "task_start_ts": 0
}

# Load task start timestamp
try:
    with open('/tmp/osint_full_page_capture_start_ts', 'r') as f:
        result["task_start_ts"] = int(f.read().strip())
except:
    pass

evidence_dir = "/home/ga/Documents/OSINT_Evidence"
if os.path.exists(evidence_dir) and os.path.isdir(evidence_dir):
    result["dir_exists"] = True

# Check full-page capture
full_png = os.path.join(evidence_dir, "onion_services_full.png")
if os.path.exists(full_png):
    result["full_png_exists"] = True
    result["full_png_mtime"] = os.path.getmtime(full_png)
    if Image:
        try:
            with Image.open(full_png) as img:
                result["full_png_width"] = img.width
                result["full_png_height"] = img.height
        except Exception as e:
            result["full_png_error"] = str(e)

# Check viewport capture
viewport_png = os.path.join(evidence_dir, "tor_check_viewport.png")
if os.path.exists(viewport_png):
    result["viewport_png_exists"] = True
    result["viewport_png_mtime"] = os.path.getmtime(viewport_png)
    if Image:
        try:
            with Image.open(viewport_png) as img:
                result["viewport_png_width"] = img.width
                result["viewport_png_height"] = img.height
        except Exception as e:
            result["viewport_png_error"] = str(e)

# Check log file
log_file = os.path.join(evidence_dir, "capture_log.txt")
if os.path.exists(log_file):
    result["log_exists"] = True
    try:
        with open(log_file, "r", encoding="utf-8") as f:
            result["log_content"] = f.read()
    except Exception as e:
        result["log_content"] = f"Error reading file: {e}"

# Check Tor history
db_path = "/tmp/osint_full_page_capture_places.sqlite"
if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        c.execute("SELECT url FROM moz_places")
        urls = [row[0] for row in c.fetchall()]
        for u in urls:
            u_lower = u.lower()
            if "community.torproject.org" in u_lower and "onion-services" in u_lower:
                result["history_community_torproject"] = True
            if "check.torproject.org" in u_lower:
                result["history_check_torproject"] = True
        conn.close()
    except Exception as e:
        result["history_error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Metrics gathered successfully.")
PYEOF

python3 /tmp/gather_metrics.py

# Clean up
rm -f /tmp/gather_metrics.py
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" 2>/dev/null || true
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json