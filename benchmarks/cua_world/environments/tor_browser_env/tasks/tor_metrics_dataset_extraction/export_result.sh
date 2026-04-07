#!/bin/bash
# export_result.sh for tor_metrics_dataset_extraction
# Extracts file sizes, timestamps, JSON contents, and CSV headers for verification

echo "=== Exporting tor_metrics_dataset_extraction results ==="

TASK_NAME="tor_metrics_dataset_extraction"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

# Find Tor Browser profile to check history
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

PLACES_DB="$PROFILE_DIR/places.sqlite"
TEMP_DB="/tmp/${TASK_NAME}_places.sqlite"

if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# We use Python to parse files, extract headers, read JSON, and format the output safely
python3 << PYEOF > /tmp/${TASK_NAME}_result.json
import os
import json
import sqlite3
import time

result = {
    "task_start": $TASK_START,
    "export_timestamp": time.time(),
    "telemetry_dir_exists": os.path.isdir("/home/ga/Documents/TorTelemetry"),
    "servers_csv": {"exists": False, "size": 0, "mtime": 0, "headers": ""},
    "clients_csv": {"exists": False, "size": 0, "mtime": 0, "headers": ""},
    "manifest": {"exists": False, "valid_json": False, "content": None},
    "history_metrics_visited": False
}

def get_csv_info(path, key):
    if os.path.exists(path) and os.path.isfile(path):
        result[key]["exists"] = True
        result[key]["size"] = os.path.getsize(path)
        result[key]["mtime"] = os.path.getmtime(path)
        try:
            with open(path, 'r', encoding='utf-8', errors='ignore') as f:
                # Read first line as headers
                result[key]["headers"] = f.readline().strip()
        except Exception as e:
            result[key]["headers"] = f"ERROR_READING_FILE: {str(e)}"

get_csv_info("/home/ga/Documents/TorTelemetry/servers.csv", "servers_csv")
get_csv_info("/home/ga/Documents/TorTelemetry/clients.csv", "clients_csv")

manifest_path = "/home/ga/Documents/TorTelemetry/ingest_manifest.json"
if os.path.exists(manifest_path) and os.path.isfile(manifest_path):
    result["manifest"]["exists"] = True
    try:
        with open(manifest_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            result["manifest"]["content"] = content
            # Try parsing to confirm it is valid JSON
            json.loads(content)
            result["manifest"]["valid_json"] = True
    except Exception:
        result["manifest"]["valid_json"] = False

# Check Browser History for Tor Metrics
db_path = "$TEMP_DB"
if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        c.execute("""
            SELECT p.url FROM moz_places p
            JOIN moz_historyvisits h ON p.id = h.place_id
        """)
        for row in c.fetchall():
            if "metrics.torproject.org" in row[0].lower():
                result["history_metrics_visited"] = True
                break
        conn.close()
    except Exception:
        pass

print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json