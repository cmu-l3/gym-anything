#!/bin/bash
echo "=== Exporting export_pages_as_pdf task results ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

TASK_START_TIMESTAMP=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Helper function to check PDF properties
check_pdf() {
    local file=$1
    if [ ! -f "$file" ]; then
        echo '{"exists": false, "valid_pdf": false, "size": 0, "mtime": 0, "md5": ""}'
        return
    fi
    
    local size=$(stat -c %s "$file" 2>/dev/null || echo "0")
    local mtime=$(stat -c %Y "$file" 2>/dev/null || echo "0")
    local md5=$(md5sum "$file" 2>/dev/null | awk '{print $1}' || echo "")
    
    # Check magic bytes (%PDF)
    local magic=$(head -c 4 "$file" 2>/dev/null || echo "")
    local valid_pdf="false"
    if [ "$magic" = "%PDF" ] && [ "$size" -gt 5000 ]; then
        valid_pdf="true"
    fi
    
    echo "{\"exists\": true, \"valid_pdf\": $valid_pdf, \"size\": $size, \"mtime\": $mtime, \"md5\": \"$md5\"}"
}

RES1=$(check_pdf "/home/ga/Documents/tor_history.pdf")
RES2=$(check_pdf "/home/ga/Documents/tor_support_about.pdf")
RES3=$(check_pdf "/home/ga/Documents/tor_training_risks.pdf")

# Find Tor Browser profile for history checking
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
TEMP_DB="/tmp/export_pages_as_pdf_places.sqlite"

if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# Check browser history via python
python3 << PYEOF > /tmp/history_check.json
import sqlite3
import json
import os

db_path = "$TEMP_DB"
result = {
    "history_history_page": False,
    "history_support_page": False,
    "history_risks_page": False
}

if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        c.execute("""
            SELECT p.url, h.visit_date
            FROM moz_places p
            JOIN moz_historyvisits h ON p.id = h.place_id
            ORDER BY h.visit_date DESC
            LIMIT 200
        """)
        history = [{"url": row[0] or "", "time": row[1] or 0} for row in c.fetchall()]
        
        task_start_micro = int($TASK_START_TIMESTAMP) * 1000000
        
        for h in history:
            url = h["url"].lower()
            if h["time"] > task_start_micro:
                if "torproject.org/about/history" in url:
                    result["history_history_page"] = True
                if "support.torproject.org/about" in url:
                    result["history_support_page"] = True
                if "community.torproject.org/training/risks" in url:
                    result["history_risks_page"] = True
    except Exception as e:
        pass

print(json.dumps(result))
PYEOF

HISTORY_RES=$(cat /tmp/history_check.json 2>/dev/null || echo '{"history_history_page": false, "history_support_page": false, "history_risks_page": false}')

# Combine results into final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START_TIMESTAMP,
    "file_history": $RES1,
    "file_support": $RES2,
    "file_risks": $RES3,
    "history": $HISTORY_RES
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON" /tmp/history_check.json "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json