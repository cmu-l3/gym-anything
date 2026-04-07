#!/bin/bash
# export_result.sh for browser_security_audit_report task
# Checks if the report file was created, reads its content safely, and checks browser history

echo "=== Exporting browser_security_audit_report results ==="

TASK_NAME="browser_security_audit_report"

# 1. Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
REPORT_FILE="/home/ga/Documents/tor-audit-report.txt"

FILE_EXISTS="false"
FILE_IS_NEW="false"
FILE_SIZE=0
FILE_CONTENT_JSON="\"\""

# 2. Extract file metadata and content
if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW="true"
    fi
    FILE_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    
    # Read up to 5000 chars and safely encode as JSON string
    if command -v jq &> /dev/null; then
        FILE_CONTENT_JSON=$(head -c 5000 "$REPORT_FILE" | jq -R -s '.')
    else
        # Fallback if jq is missing
        FILE_CONTENT_JSON=$(head -c 5000 "$REPORT_FILE" | python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))')
    fi
fi

# 3. Check browser history for check.torproject.org
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

HISTORY_HAS_CHECK_TOR="false"

if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
    
    # Query history
    HISTORY_CHECK=$(python3 -c "
import sqlite3, os
db_path = '$TEMP_DB'
if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        c.execute('''SELECT p.url FROM moz_places p 
                     JOIN moz_historyvisits h ON p.id = h.place_id 
                     WHERE p.url LIKE \"%check.torproject.org%\" LIMIT 1''')
        print('true' if c.fetchone() else 'false')
    except:
        print('false')
else:
    print('false')
" 2>/dev/null)
    
    if [ "$HISTORY_CHECK" = "true" ]; then
        HISTORY_HAS_CHECK_TOR="true"
    fi
fi

# Clean up temp db
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" 2>/dev/null || true

# 4. Check if Tor Browser is running
TOR_RUNNING="false"
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" > /dev/null; then
    TOR_RUNNING="true"
fi

# 5. Export JSON to tmp
cat > /tmp/${TASK_NAME}_result.json << EOF
{
    "task": "$TASK_NAME",
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_size": $FILE_SIZE,
    "file_content": $FILE_CONTENT_JSON,
    "history_has_check_tor": $HISTORY_HAS_CHECK_TOR,
    "tor_browser_running": $TOR_RUNNING,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true

echo "=== Export complete ==="