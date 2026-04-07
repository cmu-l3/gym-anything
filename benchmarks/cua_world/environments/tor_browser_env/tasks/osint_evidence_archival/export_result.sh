#!/bin/bash
# export_result.sh for osint_evidence_archival task
# Evaluates PDFs, evidence log, and browser history via python

echo "=== Exporting osint_evidence_archival results ==="
TASK_NAME="osint_evidence_archival"

# 1. Take final screenshot
DISPLAY=:1 import -window root "/tmp/${TASK_NAME}_end.png" 2>/dev/null || \
    DISPLAY=:1 scrot "/tmp/${TASK_NAME}_end.png" 2>/dev/null || true

# 2. Find Tor Browser profile for history checking
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

PLACES_DB=""
TEMP_DB="/tmp/${TASK_NAME}_places_export.sqlite"
if [ -n "$PROFILE_DIR" ]; then
    PLACES_DB="$PROFILE_DIR/places.sqlite"
    if [ -f "$PLACES_DB" ]; then
        # Copy to avoid WAL lock
        cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
        [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
        [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
    fi
fi

# 3. Use Python to aggregate everything into JSON safely
python3 << 'PYEOF' > "/tmp/${TASK_NAME}_result.json"
import os
import json
import sqlite3

RESULT_FILE = "/tmp/osint_evidence_archival_result.json"
START_TS_FILE = "/tmp/osint_evidence_archival_start_ts"
DB_PATH = "/tmp/osint_evidence_archival_places_export.sqlite"
EVIDENCE_DIR = "/home/ga/Documents/CaseEvidence/"

# Read task start time
try:
    with open(START_TS_FILE, "r") as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

result = {
    "task_start": task_start,
    "pdfs": {},
    "log_file": {
        "exists": False,
        "contains_check_url": False,
        "contains_history_url": False,
        "contains_metrics_url": False,
        "contains_check_pdf": False,
        "contains_history_pdf": False,
        "contains_metrics_pdf": False
    },
    "history": {
        "db_found": False,
        "visited_check": False,
        "visited_history": False,
        "visited_metrics": False
    }
}

# --- Check PDFs ---
pdf_targets = [
    "evidence_01_tor_check.pdf",
    "evidence_02_tor_history.pdf",
    "evidence_03_tor_metrics.pdf"
]

for pdf in pdf_targets:
    path = os.path.join(EVIDENCE_DIR, pdf)
    info = {"exists": False, "valid": False, "size": 0, "new": False}
    if os.path.exists(path):
        info["exists"] = True
        size = os.path.getsize(path)
        mtime = os.path.getmtime(path)
        info["size"] = size
        info["new"] = mtime >= task_start
        
        # Check magic bytes for %PDF
        try:
            with open(path, "rb") as f:
                magic = f.read(4)
                if magic == b"%PDF" and size > 5120:  # > 5KB
                    info["valid"] = True
        except:
            pass
    result["pdfs"][pdf] = info

# --- Check Evidence Log ---
log_path = os.path.join(EVIDENCE_DIR, "evidence_log.txt")
if os.path.exists(log_path):
    result["log_file"]["exists"] = True
    try:
        with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read().lower()
            
            result["log_file"]["contains_check_url"] = "check.torproject.org" in content
            result["log_file"]["contains_history_url"] = "torproject.org/about/history" in content
            result["log_file"]["contains_metrics_url"] = "metrics.torproject.org" in content
            
            result["log_file"]["contains_check_pdf"] = "evidence_01_tor_check.pdf" in content
            result["log_file"]["contains_history_pdf"] = "evidence_02_tor_history.pdf" in content
            result["log_file"]["contains_metrics_pdf"] = "evidence_03_tor_metrics.pdf" in content
    except Exception as e:
        pass

# --- Check Browser History ---
if os.path.exists(DB_PATH):
    result["history"]["db_found"] = True
    try:
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute("""
            SELECT p.url
            FROM moz_places p
            JOIN moz_historyvisits h ON p.id = h.place_id
        """)
        urls = [row[0].lower() for row in c.fetchall()]
        
        for url in urls:
            if "check.torproject.org" in url:
                result["history"]["visited_check"] = True
            if "torproject.org/about/history" in url:
                result["history"]["visited_history"] = True
            if "metrics.torproject.org" in url:
                result["history"]["visited_metrics"] = True
        conn.close()
    except Exception as e:
        pass

print(json.dumps(result, indent=2))
PYEOF

# Clean up
chmod 666 "/tmp/${TASK_NAME}_result.json" 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" 2>/dev/null || true

echo "=== Export complete ==="
cat "/tmp/${TASK_NAME}_result.json"