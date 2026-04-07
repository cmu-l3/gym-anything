#!/bin/bash
echo "=== Exporting OSINT Workspace Setup Result ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot before killing Firefox (Needed for VLM trajectory)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Close Firefox gracefully to flush `prefs.js` and `places.sqlite` to disk
echo "Shutting down Firefox to sync profiles..."
pkill -15 -u ga firefox 2>/dev/null || true
sleep 3
pkill -9 -u ga firefox 2>/dev/null || true
sleep 1

# 3. Check Evidence Directory
EVIDENCE_DIR="/home/ga/Documents/OSINT_Evidence"
EVIDENCE_DIR_EXISTS="false"
if [ -d "$EVIDENCE_DIR" ]; then
    EVIDENCE_DIR_EXISTS="true"
fi

# 4. Check Agent Screenshot
SCREENSHOT_PATH="/home/ga/Documents/osint_configured.png"
AGENT_SCREENSHOT_EXISTS="false"
if [ -f "$SCREENSHOT_PATH" ]; then
    AGENT_SCREENSHOT_EXISTS="true"
fi

# 5. Parse prefs.js for Settings
PREFS_FILE="/home/ga/.mozilla/firefox/default.profile/prefs.js"
STRICT_TRACKING="false"
if [ -f "$PREFS_FILE" ] && grep -q '"browser.contentblocking.category", "strict"' "$PREFS_FILE"; then
    STRICT_TRACKING="true"
fi

DOWNLOAD_DIR=""
if [ -f "$PREFS_FILE" ] && grep -q '"browser.download.dir"' "$PREFS_FILE"; then
    # Extract the directory string from the user_pref line
    DOWNLOAD_DIR=$(grep '"browser.download.dir"' "$PREFS_FILE" | cut -d'"' -f4 | head -n 1)
fi

# 6. Parse places.sqlite for Bookmarks
PLACES_DB="/home/ga/.mozilla/firefox/default.profile/places.sqlite"
cp "$PLACES_DB" /tmp/places_copy.sqlite 2>/dev/null || true

BOOKMARK_COUNT="0"
TOOLBAR_BOOKMARK_COUNT="0"

if [ -f "/tmp/places_copy.sqlite" ]; then
    # Check if the reference document is bookmarked at all
    BOOKMARK_COUNT=$(sqlite3 /tmp/places_copy.sqlite "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk = p.id WHERE p.url LIKE '%osint_reference.html%';" 2>/dev/null || echo "0")
    
    # Check if it is specifically pinned to the Bookmarks Toolbar
    TOOLBAR_BOOKMARK_COUNT=$(sqlite3 /tmp/places_copy.sqlite "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk = p.id WHERE p.url LIKE '%osint_reference.html%' AND b.parent = (SELECT id FROM moz_bookmarks WHERE guid = 'toolbar_____');" 2>/dev/null || echo "0")
fi

# 7. Write Export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "evidence_dir_exists": $EVIDENCE_DIR_EXISTS,
    "agent_screenshot_exists": $AGENT_SCREENSHOT_EXISTS,
    "strict_tracking": $STRICT_TRACKING,
    "download_dir": "$DOWNLOAD_DIR",
    "bookmark_count": $BOOKMARK_COUNT,
    "toolbar_bookmark_count": $TOOLBAR_BOOKMARK_COUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="