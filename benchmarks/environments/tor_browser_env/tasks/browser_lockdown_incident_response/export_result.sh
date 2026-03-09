#!/bin/bash
# export_result.sh for browser_lockdown_incident_response task

echo "=== Exporting browser_lockdown_incident_response results ==="

TASK_NAME="browser_lockdown_incident_response"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Check incident_screenshot.png
SCREENSHOT="/home/ga/Desktop/incident_screenshot.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_IS_NEW="false"
SCREENSHOT_SIZE=0
if [ -f "$SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SS_MTIME=$(stat -c %Y "$SCREENSHOT" 2>/dev/null || echo "0")
    [ "$SS_MTIME" -gt "$TASK_START" ] && SCREENSHOT_IS_NEW="true"
    SCREENSHOT_SIZE=$(stat -c %s "$SCREENSHOT" 2>/dev/null || echo "0")
fi
echo "Screenshot: exists=$SCREENSHOT_EXISTS, new=$SCREENSHOT_IS_NEW, size=${SCREENSHOT_SIZE}B"

# Check incident_report.txt
REPORT="/home/ga/Desktop/incident_report.txt"
REPORT_EXISTS="false"
REPORT_IS_NEW="false"
REPORT_SIZE=0
REPORT_HAS_LOCKDOWN="false"
if [ -f "$REPORT" ]; then
    REPORT_EXISTS="true"
    RPT_MTIME=$(stat -c %Y "$REPORT" 2>/dev/null || echo "0")
    [ "$RPT_MTIME" -gt "$TASK_START" ] && REPORT_IS_NEW="true"
    REPORT_SIZE=$(stat -c %s "$REPORT" 2>/dev/null || echo "0")
    grep -qi "lockdown" "$REPORT" 2>/dev/null && REPORT_HAS_LOCKDOWN="true"
fi
echo "Report: exists=$REPORT_EXISTS, new=$REPORT_IS_NEW, has_lockdown=$REPORT_HAS_LOCKDOWN"

# Find Tor Browser profile
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

# Check security level
SECURITY_SLIDER=1
SECURITY_LEVEL="standard"
if [ -f "$PREFS_FILE" ]; then
    SLIDER_VAL=$(grep "browser.security_level.security_slider" "$PREFS_FILE" 2>/dev/null | grep -oP '[0-9]+' | tail -1 || echo "1")
    [ -n "$SLIDER_VAL" ] && SECURITY_SLIDER=$SLIDER_VAL
    case "$SECURITY_SLIDER" in
        1) SECURITY_LEVEL="standard" ;;
        2) SECURITY_LEVEL="safer" ;;
        4) SECURITY_LEVEL="safest" ;;
        *) SECURITY_LEVEL="unknown" ;;
    esac
fi
echo "Security: slider=$SECURITY_SLIDER ($SECURITY_LEVEL)"

# Check privacy.clearOnShutdown.history = true
CLEAR_HISTORY_ON_SHUTDOWN="false"
if [ -f "$PREFS_FILE" ]; then
    grep -q 'privacy\.clearOnShutdown\.history.*true' "$PREFS_FILE" 2>/dev/null && CLEAR_HISTORY_ON_SHUTDOWN="true"
fi
echo "clearOnShutdown.history: $CLEAR_HISTORY_ON_SHUTDOWN"

# Check browser.privatebrowsing.autostart = true
AUTOSTART_PRIVATE="false"
if [ -f "$PREFS_FILE" ]; then
    grep -q 'browser\.privatebrowsing\.autostart.*true' "$PREFS_FILE" 2>/dev/null && AUTOSTART_PRIVATE="true"
fi
echo "privatebrowsing.autostart: $AUTOSTART_PRIVATE"

# Check history: has check.torproject.org visit
PLACES_DB="$PROFILE_DIR/places.sqlite"
TEMP_DB="/tmp/${TASK_NAME}_places.sqlite"
HISTORY_HAS_TORPROJECT="false"
HISTORY_COUNT=0

if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true

    TORPROJECT_COUNT=$(sqlite3 "$TEMP_DB" \
        "SELECT COUNT(*) FROM moz_places WHERE url LIKE '%check.torproject.org%';" \
        2>/dev/null || echo "0")
    [ "$TORPROJECT_COUNT" -gt "0" ] && HISTORY_HAS_TORPROJECT="true"

    HISTORY_COUNT=$(sqlite3 "$TEMP_DB" \
        "SELECT COUNT(*) FROM moz_historyvisits;" \
        2>/dev/null || echo "0")
fi

# Did agent clear history? (count should be 0 or very low after clearing)
HISTORY_CLEARED="false"
[ "$HISTORY_COUNT" -lt "5" ] && HISTORY_CLEARED="true"
echo "History count: $HISTORY_COUNT, cleared: $HISTORY_CLEARED"

PREFS_EXISTS="false"
[ -f "$PREFS_FILE" ] && PREFS_EXISTS="true"

TOR_RUNNING="false"
DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" > /dev/null && TOR_RUNNING="true"

# Write result JSON
cat > /tmp/${TASK_NAME}_result.json << EOF
{
    "task": "$TASK_NAME",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_is_new": $SCREENSHOT_IS_NEW,
    "screenshot_size": $SCREENSHOT_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_is_new": $REPORT_IS_NEW,
    "report_has_lockdown": $REPORT_HAS_LOCKDOWN,
    "report_size": $REPORT_SIZE,
    "security_slider": $SECURITY_SLIDER,
    "security_level": "$SECURITY_LEVEL",
    "clear_history_on_shutdown": $CLEAR_HISTORY_ON_SHUTDOWN,
    "autostart_private_browsing": $AUTOSTART_PRIVATE,
    "history_has_check_torproject": $HISTORY_HAS_TORPROJECT,
    "history_count": $HISTORY_COUNT,
    "history_cleared": $HISTORY_CLEARED,
    "prefs_file_exists": $PREFS_EXISTS,
    "tor_browser_running": $TOR_RUNNING,
    "task_start": $TASK_START
}
EOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json
