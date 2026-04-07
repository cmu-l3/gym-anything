#!/bin/bash
# export_result.sh for forensic_dom_node_capture task

echo "=== Exporting forensic_dom_node_capture results ==="

TASK_NAME="forensic_dom_node_capture"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
EVIDENCE_DIR="/home/ga/Documents/Forensic_Evidence"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

# Initialize variables
DIR_EXISTS="false"
WIKI_EXISTS="false"
WIKI_MTIME=0
WIKI_WIDTH=0
WIKI_HEIGHT=0
STATUS_EXISTS="false"
STATUS_MTIME=0
STATUS_WIDTH=0
STATUS_HEIGHT=0
LOG_EXISTS="false"
LOG_CONTAINS_URLS="false"

if [ -d "$EVIDENCE_DIR" ]; then
    DIR_EXISTS="true"
    
    # Check Wiki Infobox Image
    if [ -f "$EVIDENCE_DIR/tor_wiki_infobox.png" ]; then
        WIKI_EXISTS="true"
        WIKI_MTIME=$(stat -c %Y "$EVIDENCE_DIR/tor_wiki_infobox.png" 2>/dev/null || echo "0")
        
        # Get dimensions using Python
        WIKI_DIMS=$(python3 -c "import json; from PIL import Image; img=Image.open('$EVIDENCE_DIR/tor_wiki_infobox.png'); print(json.dumps({'w': img.width, 'h': img.height}))" 2>/dev/null || echo '{"w":0, "h":0}')
        WIKI_WIDTH=$(echo "$WIKI_DIMS" | grep -oP '"w": \K[0-9]+' || echo "0")
        WIKI_HEIGHT=$(echo "$WIKI_DIMS" | grep -oP '"h": \K[0-9]+' || echo "0")
    fi

    # Check Status Block Image
    if [ -f "$EVIDENCE_DIR/tor_status_block.png" ]; then
        STATUS_EXISTS="true"
        STATUS_MTIME=$(stat -c %Y "$EVIDENCE_DIR/tor_status_block.png" 2>/dev/null || echo "0")
        
        # Get dimensions using Python
        STATUS_DIMS=$(python3 -c "import json; from PIL import Image; img=Image.open('$EVIDENCE_DIR/tor_status_block.png'); print(json.dumps({'w': img.width, 'h': img.height}))" 2>/dev/null || echo '{"w":0, "h":0}')
        STATUS_WIDTH=$(echo "$STATUS_DIMS" | grep -oP '"w": \K[0-9]+' || echo "0")
        STATUS_HEIGHT=$(echo "$STATUS_DIMS" | grep -oP '"h": \K[0-9]+' || echo "0")
    fi

    # Check Capture Log
    if [ -f "$EVIDENCE_DIR/capture_log.txt" ]; then
        LOG_EXISTS="true"
        if grep -qi "wikipedia.org/wiki/Tor" "$EVIDENCE_DIR/capture_log.txt" && \
           grep -qi "check.torproject.org" "$EVIDENCE_DIR/capture_log.txt"; then
            LOG_CONTAINS_URLS="true"
        fi
    fi
fi

# Check browser history for both URLs
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

HISTORY_WIKI="false"
HISTORY_CHECK="false"

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    TEMP_DB="/tmp/${TASK_NAME}_places.sqlite"
    cp "$PROFILE_DIR/places.sqlite" "$TEMP_DB" 2>/dev/null || true
    
    # Check Wiki
    WIKI_HITS=$(sqlite3 "$TEMP_DB" "SELECT COUNT(*) FROM moz_places WHERE url LIKE '%wikipedia.org/wiki/Tor_%';" 2>/dev/null || echo "0")
    if [ "$WIKI_HITS" -gt "0" ]; then HISTORY_WIKI="true"; fi

    # Check Tor Check
    CHECK_HITS=$(sqlite3 "$TEMP_DB" "SELECT COUNT(*) FROM moz_places WHERE url LIKE '%check.torproject.org%';" 2>/dev/null || echo "0")
    if [ "$CHECK_HITS" -gt "0" ]; then HISTORY_CHECK="true"; fi
    
    rm -f "$TEMP_DB" 2>/dev/null || true
fi

# Write result JSON
cat > /tmp/${TASK_NAME}_result.json << EOF
{
    "task": "$TASK_NAME",
    "task_start_time": $TASK_START,
    "dir_exists": $DIR_EXISTS,
    "wiki_image": {
        "exists": $WIKI_EXISTS,
        "mtime": $WIKI_MTIME,
        "width": $WIKI_WIDTH,
        "height": $WIKI_HEIGHT
    },
    "status_image": {
        "exists": $STATUS_EXISTS,
        "mtime": $STATUS_MTIME,
        "width": $STATUS_WIDTH,
        "height": $STATUS_HEIGHT
    },
    "log": {
        "exists": $LOG_EXISTS,
        "contains_urls": $LOG_CONTAINS_URLS
    },
    "history": {
        "visited_wiki": $HISTORY_WIKI,
        "visited_check": $HISTORY_CHECK
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json