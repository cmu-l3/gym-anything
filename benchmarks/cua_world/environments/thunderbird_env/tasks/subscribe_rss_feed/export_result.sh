#!/bin/bash
echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Capture final screenshot for VLM Verification
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Gracefully close Thunderbird so it flushes all preferences and mbox files to disk
if pgrep -f "thunderbird" > /dev/null; then
    echo "Closing Thunderbird to flush profile data..."
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "thunderbird" | awk '{print $1}' | head -n 1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        DISPLAY=:1 xdotool key ctrl+q 2>/dev/null || true
        sleep 1
        DISPLAY=:1 wmctrl -i -c "$WID" 2>/dev/null || true
    fi
    sleep 3
    # Force kill if still hanging
    pkill -f "thunderbird" 2>/dev/null || true
    sleep 2
fi

# Check if RSS account was created (prefs.js)
RSS_PREF_EXISTS="false"
if grep -arq "\"rss\"" /home/ga/.thunderbird/ 2>/dev/null; then
    RSS_PREF_EXISTS="true"
fi

# Check HTTP server logs for agent interaction
SERVER_LOG="/tmp/rss_server.log"
SERVER_GET_COUNT=$(grep -c "GET /market_news.xml" "$SERVER_LOG" 2>/dev/null || echo "0")

# Check if data was actually downloaded into an Mbox file inside Thunderbird
ARTICLE_DOWNLOADED="false"
HEADLINE="Global Equities Rebound Strongly"
if grep -arq "$HEADLINE" /home/ga/.thunderbird/ 2>/dev/null; then
    ARTICLE_DOWNLOADED="true"
fi

# Assemble JSON dump
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "rss_pref_exists": $RSS_PREF_EXISTS,
    "server_get_count": $SERVER_GET_COUNT,
    "article_downloaded": $ARTICLE_DOWNLOADED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Carefully copy to /tmp ensuring valid permissions for the host machine extractor
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="