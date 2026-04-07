#!/bin/bash
# export_result.sh for persistent_osint_dashboard
set -e

echo "=== Exporting persistent_osint_dashboard task results ==="

TASK_NAME="persistent_osint_dashboard"
TASK_START_TS=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

# 2. Check Tor Browser Profile (Prefs and History)
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

# Read preference
AUTOSTART_PRIVATE="true"
if [ -f "$PROFILE_DIR/prefs.js" ]; then
    if grep -q 'browser\.privatebrowsing\.autostart.*false' "$PROFILE_DIR/prefs.js" 2>/dev/null; then
        AUTOSTART_PRIVATE="false"
    fi
fi

# Copy DB to avoid locking issues
PLACES_DB="$PROFILE_DIR/places.sqlite"
TEMP_DB="/tmp/places_export_$$.sqlite"

LOCAL_FILE_VISITED="false"
CHECK_TOR_VISITED="false"

if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true

    # Query history using Python for robust SQLite parsing
    python3 << PYEOF > /tmp/${TASK_NAME}_history.json
import sqlite3
import json

db_path = "$TEMP_DB"
task_start = $TASK_START_TS
result = {
    "local_file_visited": False,
    "check_tor_visited": False
}

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    
    c.execute("""
        SELECT p.url, h.visit_date
        FROM moz_places p
        JOIN moz_historyvisits h ON p.id = h.place_id
    """)
    rows = c.fetchall()
    
    for row in rows:
        url = row["url"] or ""
        visit_date = (row["visit_date"] or 0) / 1000000  # Convert microseconds to seconds
        
        # Only count visits after task start
        if visit_date >= task_start:
            if "osint_dashboard.html" in url.lower() and url.startswith("file://"):
                result["local_file_visited"] = True
            if "check.torproject.org" in url.lower():
                result["check_tor_visited"] = True
                
    conn.close()
except Exception as e:
    result["error"] = str(e)

with open("/tmp/${TASK_NAME}_history.json", "w") as f:
    json.dump(result, f)
PYEOF

    LOCAL_FILE_VISITED=$(python3 -c "import json; print(json.load(open('/tmp/${TASK_NAME}_history.json')).get('local_file_visited', False))" | tr '[:upper:]' '[:lower:]')
    CHECK_TOR_VISITED=$(python3 -c "import json; print(json.load(open('/tmp/${TASK_NAME}_history.json')).get('check_tor_visited', False))" | tr '[:upper:]' '[:lower:]')

    rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# 3. Check HTML Dashboard
HTML_PATH="/home/ga/Documents/osint_dashboard.html"
HTML_EXISTS="false"
HTML_HAS_CHECK_LINK="false"
HTML_HAS_METRICS_LINK="false"

if [ -f "$HTML_PATH" ]; then
    HTML_EXISTS="true"
    if grep -qi "check.torproject.org" "$HTML_PATH"; then HTML_HAS_CHECK_LINK="true"; fi
    if grep -qi "metrics.torproject.org" "$HTML_PATH"; then HTML_HAS_METRICS_LINK="true"; fi
fi

# 4. Check Desktop Launcher
DESKTOP_PATH="/home/ga/Desktop/OSINT-Dashboard.desktop"
DESKTOP_EXISTS="false"
DESKTOP_IS_EXECUTABLE="false"
DESKTOP_NAME=""
DESKTOP_EXEC=""

if [ -f "$DESKTOP_PATH" ]; then
    DESKTOP_EXISTS="true"
    if [ -x "$DESKTOP_PATH" ]; then DESKTOP_IS_EXECUTABLE="true"; fi
    
    # Extract Name and Exec lines
    DESKTOP_NAME=$(grep -E "^Name\s*=" "$DESKTOP_PATH" | head -1 | cut -d'=' -f2- | xargs || echo "")
    DESKTOP_EXEC=$(grep -E "^Exec\s*=" "$DESKTOP_PATH" | head -1 | cut -d'=' -f2- | xargs || echo "")
fi

# Escape JSON strings
escape_json() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    echo "$str"
}

DESKTOP_NAME_ESC=$(escape_json "$DESKTOP_NAME")
DESKTOP_EXEC_ESC=$(escape_json "$DESKTOP_EXEC")

# 5. Compile Result JSON
cat > /tmp/${TASK_NAME}_result.json << EOF
{
    "task_start_ts": $TASK_START_TS,
    "autostart_private_browsing": $AUTOSTART_PRIVATE,
    "html_exists": $HTML_EXISTS,
    "html_has_check_link": $HTML_HAS_CHECK_LINK,
    "html_has_metrics_link": $HTML_HAS_METRICS_LINK,
    "desktop_exists": $DESKTOP_EXISTS,
    "desktop_is_executable": $DESKTOP_IS_EXECUTABLE,
    "desktop_name": "$DESKTOP_NAME_ESC",
    "desktop_exec": "$DESKTOP_EXEC_ESC",
    "history_local_file_visited": $LOCAL_FILE_VISITED,
    "history_check_tor_visited": $CHECK_TOR_VISITED
}
EOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json