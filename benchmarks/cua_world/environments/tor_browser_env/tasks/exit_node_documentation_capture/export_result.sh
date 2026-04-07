#!/bin/bash
echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check Directory
DIR_EXISTS="false"
if [ -d "/home/ga/Documents/OpsecLogs" ]; then
    DIR_EXISTS="true"
fi

# Check HTML Source File
HTML_EXISTS="false"
HTML_SIZE=0
HTML_NEW="false"
if [ -f "/home/ga/Documents/OpsecLogs/check_source.html" ]; then
    HTML_EXISTS="true"
    HTML_SIZE=$(stat -c %s "/home/ga/Documents/OpsecLogs/check_source.html" 2>/dev/null || echo "0")
    MTIME=$(stat -c %Y "/home/ga/Documents/OpsecLogs/check_source.html" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        HTML_NEW="true"
    fi
    # Copy for python verifier to read cleanly
    cp "/home/ga/Documents/OpsecLogs/check_source.html" "/tmp/check_source.html" 2>/dev/null || true
    chmod 666 "/tmp/check_source.html" 2>/dev/null || true
fi

# Check IP Text File
IP_EXISTS="false"
IP_NEW="false"
IP_CONTENT=""
if [ -f "/home/ga/Documents/OpsecLogs/exit_ip.txt" ]; then
    IP_EXISTS="true"
    MTIME=$(stat -c %Y "/home/ga/Documents/OpsecLogs/exit_ip.txt" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        IP_NEW="true"
    fi
    # Read the content to supply to verifier JSON
    IP_CONTENT=$(head -n 1 "/home/ga/Documents/OpsecLogs/exit_ip.txt" | tr -d '\n' | tr -d '\r' | sed 's/"/\\"/g')
fi

# Verify History
HISTORY_VERIFIED="false"
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

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PROFILE_DIR/places.sqlite" "$TEMP_DB" 2>/dev/null || true
    VISIT_COUNT=$(sqlite3 "$TEMP_DB" "SELECT COUNT(*) FROM moz_places WHERE url LIKE '%check.torproject.org%';" 2>/dev/null || echo "0")
    if [ "$VISIT_COUNT" -gt 0 ]; then
        HISTORY_VERIFIED="true"
    fi
    rm -f "$TEMP_DB"
fi

# Build JSON Result safely using temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "dir_exists": $DIR_EXISTS,
    "html_exists": $HTML_EXISTS,
    "html_size": $HTML_SIZE,
    "html_new": $HTML_NEW,
    "ip_exists": $IP_EXISTS,
    "ip_new": $IP_NEW,
    "ip_content": "$IP_CONTENT",
    "history_verified": $HISTORY_VERIFIED
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="