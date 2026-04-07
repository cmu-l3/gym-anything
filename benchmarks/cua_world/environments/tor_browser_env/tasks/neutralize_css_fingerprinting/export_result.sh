#!/bin/bash
# export_result.sh for neutralize_css_fingerprinting task
# Extracts preference state and output file metadata

echo "=== Exporting neutralize_css_fingerprinting results ==="

TASK_NAME="neutralize_css_fingerprinting"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/safe_render.png"

# Take final environment screenshot
DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

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

# Read preferences
FONT_PREF=1    # 1 is default (allow document fonts)
COLOR_PREF=0   # 0 is default (only with high contrast)
SMOOTH_PREF="true" # true is default

if [ -f "$PREFS_FILE" ]; then
    # browser.display.use_document_fonts
    VAL=$(grep -oP 'user_pref\("browser\.display\.use_document_fonts",\s*\K[0-9]+' "$PREFS_FILE" | tail -1 || echo "")
    if [ -n "$VAL" ]; then FONT_PREF=$VAL; fi

    # browser.display.document_color_use
    VAL=$(grep -oP 'user_pref\("browser\.display\.document_color_use",\s*\K[0-9]+' "$PREFS_FILE" | tail -1 || echo "")
    if [ -n "$VAL" ]; then COLOR_PREF=$VAL; fi

    # general.smoothScroll
    if grep -q 'user_pref("general.smoothScroll", false)' "$PREFS_FILE"; then
        SMOOTH_PREF="false"
    fi
fi

# Check evidence file
FILE_EXISTS="false"
FILE_IS_NEW="false"
FILE_SIZE=0

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW="true"
    fi
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
fi

# Check if browser is still running
APP_RUNNING="false"
if pgrep -f "firefox.*TorBrowser\|tor-browser" > /dev/null; then
    APP_RUNNING="true"
fi

# Generate JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task": "$TASK_NAME",
    "prefs": {
        "use_document_fonts": $FONT_PREF,
        "document_color_use": $COLOR_PREF,
        "smooth_scroll": $SMOOTH_PREF
    },
    "output_file": {
        "exists": $FILE_EXISTS,
        "is_new": $FILE_IS_NEW,
        "size_bytes": $FILE_SIZE
    },
    "app_running": $APP_RUNNING,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Make result readable by verifier
sudo cp "$TEMP_JSON" /tmp/task_result.json
sudo chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json