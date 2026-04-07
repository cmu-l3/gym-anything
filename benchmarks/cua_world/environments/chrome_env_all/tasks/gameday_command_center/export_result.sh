#!/bin/bash
echo "=== Exporting Game Day Command Center Result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract open tabs using CDP before closing Chrome
echo "Extracting open tabs via CDP..."
# Attempt to use chrome-cdp-util if available, otherwise curl directly
if command -v chrome-cdp-util &> /dev/null; then
    chrome-cdp-util tabs-json > /tmp/cdp_tabs.json 2>/dev/null || echo "[]" > /tmp/cdp_tabs.json
else
    # Fallback to curl
    curl -s http://localhost:9222/json > /tmp/cdp_tabs.json || curl -s http://localhost:1337/json > /tmp/cdp_tabs.json || echo "[]" > /tmp/cdp_tabs.json
fi
chmod 644 /tmp/cdp_tabs.json

# Gracefully close Chrome to flush Preferences and Bookmarks to disk
echo "Flushing Chrome data to disk..."
pkill -f chrome 2>/dev/null || true
sleep 3
pkill -9 -f chrome 2>/dev/null || true
sleep 1

# Check if checklist exists
CHECKLIST_EXISTS="false"
if [ -f "/home/ga/Desktop/pregame_checklist.txt" ]; then
    CHECKLIST_EXISTS="true"
fi

# Output JSON summary just for reference (verifier uses actual files)
cat > /tmp/export_summary.json << EOF
{
    "checklist_exists": $CHECKLIST_EXISTS,
    "cdp_tabs_exported": true,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "=== Export complete ==="