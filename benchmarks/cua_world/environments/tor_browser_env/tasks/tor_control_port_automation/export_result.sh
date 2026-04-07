#!/bin/bash
# export_result.sh for tor_control_port_automation
# Collects evidence: output files, script contents, and browser history

echo "=== Exporting tor_control_port_automation results ==="

# 1. Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

# 2. Extract base64 of the required files to safely embed in JSON
file_to_b64() {
    if [ -f "$1" ]; then
        base64 -w 0 "$1"
    else
        echo ""
    fi
}

SCRIPT_B64=$(file_to_b64 "/home/ga/Documents/tor_control.py")
VERSION_B64=$(file_to_b64 "/home/ga/Documents/tor_version.txt")
IP_BEFORE_B64=$(file_to_b64 "/home/ga/Documents/ip_before.txt")
IP_AFTER_B64=$(file_to_b64 "/home/ga/Documents/ip_after.txt")

# Check creation times to prevent gaming (doing nothing and having old files)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
SCRIPT_CREATED_DURING_TASK="false"
if [ -f "/home/ga/Documents/tor_control.py" ]; then
    SCRIPT_MTIME=$(stat -c %Y "/home/ga/Documents/tor_control.py" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -ge "$TASK_START" ]; then
        SCRIPT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check Browser History for check.torproject.org
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
TEMP_DB="/tmp/places_export_$$.sqlite"

HISTORY_CHECK_TORPROJECT="false"
if [ -f "$PLACES_DB" ]; then
    # Copy DB to avoid lock conflicts
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
    
    # Query checking for the specific verification URL
    CHECK_RESULT=$(sqlite3 "$TEMP_DB" "SELECT url FROM moz_places WHERE url LIKE '%check.torproject.org%' LIMIT 1;" 2>/dev/null || echo "")
    if [ -n "$CHECK_RESULT" ]; then
        HISTORY_CHECK_TORPROJECT="true"
    fi
    rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# 4. Generate Results JSON safely
cat > /tmp/tor_control_result.json << EOF
{
  "task_start_timestamp": $TASK_START,
  "script_created_during_task": $SCRIPT_CREATED_DURING_TASK,
  "history_has_check_torproject": $HISTORY_CHECK_TORPROJECT,
  "script_b64": "$SCRIPT_B64",
  "version_b64": "$VERSION_B64",
  "ip_before_b64": "$IP_BEFORE_B64",
  "ip_after_b64": "$IP_AFTER_B64"
}
EOF

chmod 666 /tmp/tor_control_result.json 2>/dev/null || true
echo "=== Export complete ==="