#!/bin/bash
echo "=== Exporting Task Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot (might be desktop if Firefox was gracefully closed)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if Firefox is running (Task dictates it should be closed)
if pgrep -f firefox > /dev/null; then
    FF_RUNNING="true"
else
    FF_RUNNING="false"
fi

PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
PREFS_FILE="$PROFILE_DIR/prefs.js"
PLACES_DB="$PROFILE_DIR/places.sqlite"

# Wait for background SQLite WAL flushes if Firefox was just closed
sleep 3

# Safely extract Firefox Preferences
HOMEPAGE=""
TOOLBAR_VIS=""
SANITIZE="false"

if [ -f "$PREFS_FILE" ]; then
    # Parse strings: user_pref("key", "value");
    HOMEPAGE=$(grep 'user_pref("browser.startup.homepage"' "$PREFS_FILE" | awk -F'"' '{print $4}')
    TOOLBAR_VIS=$(grep 'user_pref("browser.toolbars.bookmarks.visibility"' "$PREFS_FILE" | awk -F'"' '{print $4}')
    
    # Parse booleans: user_pref("key", true);
    if grep -q 'user_pref("privacy.sanitize.sanitizeOnShutdown", true)' "$PREFS_FILE"; then
        SANITIZE="true"
    fi
fi

# Extract Bookmarks Safely (copy DB to bypass locks)
cp "$PLACES_DB" /tmp/places_copy.sqlite 2>/dev/null || true

BOOKMARKS_JSON="[]"
if [ -f "/tmp/places_copy.sqlite" ]; then
    # Query extracts URL, Title, and Parent ID (Bookmarks Toolbar is typically parent=3)
    QUERY="SELECT json_group_array(json_object('url', p.url, 'title', b.title, 'parent', b.parent)) FROM moz_bookmarks b JOIN moz_places p ON b.fk = p.id WHERE b.type = 1;"
    BOOKMARKS_JSON=$(sqlite3 /tmp/places_copy.sqlite "$QUERY" 2>/dev/null || echo "[]")
fi

if [ -z "$BOOKMARKS_JSON" ]; then
    BOOKMARKS_JSON="[]"
fi

# Write results to a structured JSON file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "firefox_running": $FF_RUNNING,
    "prefs": {
        "homepage": "$HOMEPAGE",
        "toolbar_visibility": "$TOOLBAR_VIS",
        "sanitize_on_shutdown": $SANITIZE
    },
    "bookmarks": $BOOKMARKS_JSON
}
EOF

# Make result accessible to the verifier
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="