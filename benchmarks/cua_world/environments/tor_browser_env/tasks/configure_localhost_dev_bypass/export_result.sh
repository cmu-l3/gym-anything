#!/bin/bash
set -e
echo "=== Exporting configure_localhost_dev_bypass task results ==="

# Terminate netcat if it's still running (forces buffer to flush to file)
pkill -f "nc -l -p 8080" 2>/dev/null || true
sleep 1

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TARGET_FILE="/home/ga/Documents/tor_headers.txt"

FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
GET_REQUEST_FOUND="false"
AUTHENTIC_USER_AGENT="false"
HOST_HEADER_FOUND="false"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    
    # Check if created/modified after task started
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Search file contents
    if grep -qE "GET /tor-dev-test HTTP/1\.[01]" "$TARGET_FILE" 2>/dev/null; then
        GET_REQUEST_FOUND="true"
    fi
    
    if grep -qiE "Host: (127\.0\.0\.1|localhost):8080" "$TARGET_FILE" 2>/dev/null; then
        HOST_HEADER_FOUND="true"
    fi
    
    if grep -qi "User-Agent: Mozilla/5.0" "$TARGET_FILE" 2>/dev/null; then
        AUTHENTIC_USER_AGENT="true"
    fi
fi

# Check Tor Browser profile for correct configuration
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

PREFS_FILE="$PROFILE_DIR/prefs.js"
CONFIG_MODIFIED="false"
if [ -f "$PREFS_FILE" ]; then
    # Verify the specific preference was overridden
    if grep -q 'user_pref("network.proxy.allow_hijacking_localhost", false)' "$PREFS_FILE" 2>/dev/null; then
        CONFIG_MODIFIED="true"
    fi
fi

# Check browser history for the test URL
PLACES_DB="$PROFILE_DIR/places.sqlite"
TEMP_DB="/tmp/places_export_$$"
BROWSER_HISTORY="false"

if [ -f "$PLACES_DB" ]; then
    # Use copy for concurrent safety
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    
    if command -v sqlite3 >/dev/null 2>&1; then
        HISTORY_MATCH=$(sqlite3 "$TEMP_DB" "SELECT COUNT(*) FROM moz_places WHERE url LIKE 'http://127.0.0.1:8080/tor-dev-test%';" 2>/dev/null || echo "0")
        if [ "$HISTORY_MATCH" -gt 0 ]; then
            BROWSER_HISTORY="true"
        fi
    fi
    
    rm -f "$TEMP_DB" "${TEMP_DB}-wal" 2>/dev/null || true
fi

# Generate JSON Output
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "get_request_found": $GET_REQUEST_FOUND,
    "authentic_user_agent": $AUTHENTIC_USER_AGENT,
    "host_header_found": $HOST_HEADER_FOUND,
    "config_modified": $CONFIG_MODIFIED,
    "browser_history": $BROWSER_HISTORY,
    "task_start_time": $TASK_START
}
EOF

# Move to standard location securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json