#!/bin/bash
# export_result.sh for configure_noscript_exceptions
# Gathers output file metadata and prefs.js settings

echo "=== Exporting configure_noscript_exceptions results ==="

TASK_NAME="configure_noscript_exceptions"

# 1. Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

# 2. Extract baseline task start timestamp
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# 3. Check for the exported NoScript policy file
OUTPUT_FILE="/home/ga/Documents/noscript_policy.txt"
FILE_EXISTS="false"
FILE_IS_NEW="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW="true"
    fi
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
fi

# 4. Check Tor Browser profile for Security Level (prefs.js)
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
SECURITY_SLIDER=1
SECURITY_LEVEL="standard"

if [ -f "$PREFS_FILE" ]; then
    SLIDER_VAL=$(grep "browser.security_level.security_slider" "$PREFS_FILE" 2>/dev/null | grep -oP '[0-9]+' | tail -1 || echo "1")
    if [ -n "$SLIDER_VAL" ]; then
        SECURITY_SLIDER=$SLIDER_VAL
    fi
    case "$SECURITY_SLIDER" in
        1) SECURITY_LEVEL="standard" ;;
        2) SECURITY_LEVEL="safer" ;;
        4) SECURITY_LEVEL="safest" ;;
        *) SECURITY_LEVEL="unknown" ;;
    esac
fi

# 5. Check if Tor Browser is still running
TOR_RUNNING="false"
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" > /dev/null; then
    TOR_RUNNING="true"
fi

# 6. Generate JSON result file
cat > /tmp/${TASK_NAME}_result.json << EOF
{
    "task": "$TASK_NAME",
    "task_start_ts": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_size": $FILE_SIZE,
    "security_slider": $SECURITY_SLIDER,
    "security_level": "$SECURITY_LEVEL",
    "tor_browser_running": $TOR_RUNNING,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json