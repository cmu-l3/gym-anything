#!/bin/bash
# export_result.sh - Post-task hook for web_perf_waterfall_analysis

echo "=== Exporting task results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Kill Firefox to flush history database (WAL checkpoint)
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Read metadata
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))

PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
    # Fallback if file was deleted or not found initially
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "")
fi
PLACES_DB="$PROFILE_DIR/places.sqlite"

# 4. Analyze Browser History (SQL Check)
# We want to know if they visited the target domains
HISTORY_JSON="{}"
if [ -f "$PLACES_DB" ]; then
    # Force checkpoint if possible
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    
    # Copy to temp to avoid locks
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    
    if [ -f "$TEMP_DB" ]; then
        # Python script to check history for specific domains
        HISTORY_JSON=$(python3 -c "
import sqlite3, json
try:
    conn = sqlite3.connect('$TEMP_DB')
    cursor = conn.cursor()
    domains = ['ycombinator.com', 'wikipedia.org', 'mozilla.org', 'python.org', 'github.com']
    results = {}
    for d in domains:
        # Check for visits after task start
        query = f\"SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id WHERE p.url LIKE '%{d}%' AND h.visit_date > {TASK_START_US}\"
        cursor.execute(query)
        count = cursor.fetchone()[0]
        results[d] = count
    print(json.dumps(results))
    conn.close()
except Exception as e:
    print(json.dumps({'error': str(e)}))
")
        rm -f "$TEMP_DB"
    fi
fi

# 5. Analyze HAR Files and Report (Python Script)
# We use Python here to robustness in parsing JSON files
python3 << PYEOF
import json
import os
import glob
import time

task_start = $TASK_START
har_dir = "/home/ga/Documents/har_exports"
report_path = "/home/ga/Documents/performance_report.json"
screenshot_path = "/tmp/task_final.png"
history_data = $HISTORY_JSON

result = {
    "task_start": task_start,
    "timestamp": time.time(),
    "screenshot_exists": os.path.exists(screenshot_path),
    "history": history_data,
    "har_files": [],
    "report": {
        "exists": False,
        "fresh": False,
        "valid_json": False,
        "content": None
    }
}

# --- Analyze HAR Files ---
if os.path.exists(har_dir):
    har_files = glob.glob(os.path.join(har_dir, "*.har"))
    for hf in har_files:
        stats = os.stat(hf)
        is_fresh = stats.st_mtime > task_start
        file_info = {
            "filename": os.path.basename(hf),
            "size": stats.st_size,
            "fresh": is_fresh,
            "valid_har": False,
            "entry_count": 0,
            "domains": []
        }
        
        # Parse HAR content
        try:
            with open(hf, 'r', encoding='utf-8', errors='ignore') as f:
                data = json.load(f)
                if "log" in data and "entries" in data["log"]:
                    file_info["valid_har"] = True
                    entries = data["log"]["entries"]
                    file_info["entry_count"] = len(entries)
                    
                    # Extract unique domains from first 50 entries to avoid huge processing
                    domains = set()
                    for e in entries[:50]:
                        url = e.get("request", {}).get("url", "")
                        if "://" in url:
                            domain = url.split("/")[2]
                            domains.add(domain)
                    file_info["domains"] = list(domains)
        except Exception:
            pass
            
        result["har_files"].append(file_info)

# --- Analyze Performance Report ---
if os.path.exists(report_path):
    result["report"]["exists"] = True
    stats = os.stat(report_path)
    if stats.st_mtime > task_start:
        result["report"]["fresh"] = True
    
    try:
        with open(report_path, 'r', encoding='utf-8') as f:
            content = json.load(f)
            result["report"]["valid_json"] = True
            result["report"]["content"] = content
    except Exception:
        pass

# Write result to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# 6. Secure the output
chmod 644 /tmp/task_result.json 2>/dev/null || true

echo "Result summary:"
cat /tmp/task_result.json
echo "=== Export complete ==="