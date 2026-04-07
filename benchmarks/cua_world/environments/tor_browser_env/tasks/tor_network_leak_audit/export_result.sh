#!/bin/bash
# export_result.sh for tor_network_leak_audit task
# Exports file metadata and query history

echo "=== Exporting tor_network_leak_audit results ==="

TASK_NAME="tor_network_leak_audit"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# File Validation Function
check_file() {
    local filepath=$1
    local exists="false"
    local created_during_task="false"
    local size=0
    
    if [ -f "$filepath" ]; then
        exists="true"
        size=$(stat -c %s "$filepath" 2>/dev/null || echo "0")
        mtime=$(stat -c %Y "$filepath" 2>/dev/null || echo "0")
        if [ "$mtime" -ge "$TASK_START" ]; then
            created_during_task="true"
        fi
    fi
    echo "{\"exists\": $exists, \"created_during_task\": $created_during_task, \"size_bytes\": $size}"
}

REPORT_STATS=$(check_file "/home/ga/Documents/tor_leak_audit.txt")
HTML_STATS=$(check_file "/home/ga/Documents/sockets_source.html")
IMAGE_STATS=$(check_file "/home/ga/Documents/telemetry_status.png")

# Query places.sqlite for onion history
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

ONION_VISITED="false"
if [ -n "$PROFILE_DIR" ]; then
    PLACES_DB="$PROFILE_DIR/places.sqlite"
    TEMP_DB="/tmp/${TASK_NAME}_places.sqlite"
    
    # Safe copy
    if [ -f "$PLACES_DB" ]; then
        cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
        [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
        [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
        
        DUCKDUCKGO_RESULT=$(sqlite3 "$TEMP_DB" "
            SELECT p.url FROM moz_places p
            JOIN moz_historyvisits h ON p.id = h.place_id
            WHERE LOWER(p.url) LIKE '%duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion%'
            LIMIT 1;
        " 2>/dev/null || echo "")
        
        if [ -n "$DUCKDUCKGO_RESULT" ]; then
            ONION_VISITED="true"
        fi
        
        rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" 2>/dev/null || true
    fi
fi

# Build result.json
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "onion_visited": $ONION_VISITED,
    "report_file": $REPORT_STATS,
    "html_file": $HTML_STATS,
    "image_file": $IMAGE_STATS
}
EOF

# Make readable to verifier
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json