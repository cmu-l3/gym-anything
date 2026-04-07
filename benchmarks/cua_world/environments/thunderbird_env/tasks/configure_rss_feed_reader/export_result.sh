#!/bin/bash
echo "=== Exporting RSS Feed Reader results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TB_DIR="/home/ga/.thunderbird/default-release"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if Thunderbird is running
TB_RUNNING="false"
if pgrep -f "thunderbird" > /dev/null; then
    TB_RUNNING="true"
fi

# Give Thunderbird a moment to flush prefs.js to disk if it was just modified
sleep 2

# Check preferences for Feed account creation
HAS_RSS_PREF="false"
if grep -q "\"rss\"" "$TB_DIR/prefs.js" 2>/dev/null; then
    HAS_RSS_PREF="true"
fi

HAS_MARKET_INTEL_PREF="false"
if grep -qi "Market Intelligence" "$TB_DIR/prefs.js" 2>/dev/null; then
    HAS_MARKET_INTEL_PREF="true"
fi

# Check if the feed URL was subscribed
FEED_URL_FOUND="false"
if grep -rq "http://localhost:8080/industry_news.xml" "$TB_DIR" 2>/dev/null; then
    FEED_URL_FOUND="true"
fi

# Check if articles were actually downloaded (mbox parsing)
ARTICLES_DOWNLOADED="false"
DOWNLOADED_DURING_TASK="false"
ARTICLE_FILE=$(grep -rl "Globex Corp Announces Q3 Results" "$TB_DIR/Mail" 2>/dev/null | head -1)

if [ -n "$ARTICLE_FILE" ]; then
    ARTICLES_DOWNLOADED="true"
    FILE_MTIME=$(stat -c %Y "$ARTICLE_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        DOWNLOADED_DURING_TASK="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "tb_running": $TB_RUNNING,
    "has_rss_pref": $HAS_RSS_PREF,
    "has_market_intel_pref": $HAS_MARKET_INTEL_PREF,
    "feed_url_found": $FEED_URL_FOUND,
    "articles_downloaded": $ARTICLES_DOWNLOADED,
    "downloaded_during_task": $DOWNLOADED_DURING_TASK,
    "article_file_path": "${ARTICLE_FILE:-none}",
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false")
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Kill the internal feed server
pkill -f "http.server 8080" > /dev/null 2>&1 || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="