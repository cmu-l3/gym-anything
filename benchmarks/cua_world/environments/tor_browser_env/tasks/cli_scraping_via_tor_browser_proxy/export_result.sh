#!/bin/bash
echo "=== Exporting cli_scraping_via_tor_browser_proxy results ==="

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
echo "Task start timestamp: $TASK_START"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || import -window root /tmp/task_final.png 2>/dev/null || true

# Initialize variables
SCRIPT_EXISTS="false"
SCRIPT_NEW="false"
SCRIPT_CONTENT=""
IP_JSON_EXISTS="false"
IP_JSON_NEW="false"
IP_JSON_CONTENT=""
DDG_HTML_EXISTS="false"
DDG_HTML_NEW="false"
DDG_HTML_SIZE=0
DDG_HAS_CONTENT="false"

# Check script
if [ -f "/home/ga/Documents/tor_scraper.sh" ]; then
    SCRIPT_EXISTS="true"
    MTIME=$(stat -c %Y "/home/ga/Documents/tor_scraper.sh" 2>/dev/null || echo "0")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        SCRIPT_NEW="true"
    fi
    # Base64 encode the script content to avoid JSON escaping issues
    SCRIPT_CONTENT=$(cat "/home/ga/Documents/tor_scraper.sh" | base64 -w 0 2>/dev/null || echo "")
fi

# Check IP JSON
if [ -f "/home/ga/Documents/tor_ip.json" ]; then
    IP_JSON_EXISTS="true"
    MTIME=$(stat -c %Y "/home/ga/Documents/tor_ip.json" 2>/dev/null || echo "0")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        IP_JSON_NEW="true"
    fi
    IP_JSON_CONTENT=$(cat "/home/ga/Documents/tor_ip.json" | base64 -w 0 2>/dev/null || echo "")
fi

# Check DDG HTML
if [ -f "/home/ga/Documents/ddg_onion.html" ]; then
    DDG_HTML_EXISTS="true"
    MTIME=$(stat -c %Y "/home/ga/Documents/ddg_onion.html" 2>/dev/null || echo "0")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        DDG_HTML_NEW="true"
    fi
    DDG_HTML_SIZE=$(stat -c %s "/home/ga/Documents/ddg_onion.html" 2>/dev/null || echo "0")
    if grep -qi "duckduckgo" "/home/ga/Documents/ddg_onion.html" 2>/dev/null; then
        DDG_HAS_CONTENT="true"
    fi
fi

# Check Tor Browser
TOR_RUNNING="false"
if pgrep -u ga -f "firefox.*TorBrowser\|tor-browser" > /dev/null; then
    TOR_RUNNING="true"
fi

# Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "script_exists": $SCRIPT_EXISTS,
    "script_new": $SCRIPT_NEW,
    "script_content_b64": "$SCRIPT_CONTENT",
    "ip_json_exists": $IP_JSON_EXISTS,
    "ip_json_new": $IP_JSON_NEW,
    "ip_json_content_b64": "$IP_JSON_CONTENT",
    "ddg_html_exists": $DDG_HTML_EXISTS,
    "ddg_html_new": $DDG_HTML_NEW,
    "ddg_html_size": $DDG_HTML_SIZE,
    "ddg_has_content": $DDG_HAS_CONTENT,
    "tor_running": $TOR_RUNNING
}
EOF

rm -f /tmp/cli_scraping_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/cli_scraping_result.json
chmod 666 /tmp/cli_scraping_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="