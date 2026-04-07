#!/bin/bash
# export_result.sh for configure_strict_offline_file_handling task
# Queries prefs.js for deep configurations and verifies downloaded artifact

echo "=== Exporting configure_strict_offline_file_handling results ==="

TASK_NAME="configure_strict_offline_file_handling"
TARGET_DIR="/home/ga/Documents/MalwareAnalysis"
TARGET_FILE="$TARGET_DIR/dummy.pdf"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

# 2. Locate Tor Browser profile
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
PREFS_EXISTS="false"
if [ -f "$PREFS_FILE" ]; then
    PREFS_EXISTS="true"
fi

# 3. Analyze Preferences
PDFJS_DISABLED="false"
MEDIA_STANDALONE_DISABLED="false"
CLIPBOARD_EVENTS_DISABLED="false"
DOWNLOAD_DIR_PROMPT="false"

if [ "$PREFS_EXISTS" = "true" ]; then
    # pdfjs.disabled -> should be true
    if grep -q 'user_pref("pdfjs.disabled", true);' "$PREFS_FILE" 2>/dev/null; then
        PDFJS_DISABLED="true"
    fi
    
    # media.play-stand-alone -> should be false
    if grep -q 'user_pref("media.play-stand-alone", false);' "$PREFS_FILE" 2>/dev/null; then
        MEDIA_STANDALONE_DISABLED="true"
    fi
    
    # dom.event.clipboardevents.enabled -> should be false
    if grep -q 'user_pref("dom.event.clipboardevents.enabled", false);' "$PREFS_FILE" 2>/dev/null; then
        CLIPBOARD_EVENTS_DISABLED="true"
    fi
    
    # browser.download.useDownloadDir -> should be false
    if grep -q 'user_pref("browser.download.useDownloadDir", false);' "$PREFS_FILE" 2>/dev/null; then
        DOWNLOAD_DIR_PROMPT="true"
    fi
fi

# 4. Analyze File and Directory
DIRECTORY_CREATED="false"
if [ -d "$TARGET_DIR" ]; then
    DIRECTORY_CREATED="true"
fi

ARTIFACT_EXISTS="false"
ARTIFACT_IS_NEW="false"
ARTIFACT_HEADER="UNKNOWN"

if [ -f "$TARGET_FILE" ]; then
    ARTIFACT_EXISTS="true"
    
    # Check creation time for anti-gaming
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        ARTIFACT_IS_NEW="true"
    fi
    
    # Extract first 4 bytes to check PDF magic header
    ARTIFACT_HEADER=$(head -c 4 "$TARGET_FILE" 2>/dev/null || echo "FAIL")
fi

# Check if Tor is running
TOR_RUNNING="false"
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" > /dev/null; then
    TOR_RUNNING="true"
fi

# 5. Build Final JSON
cat > /tmp/${TASK_NAME}_result.json << EOF
{
    "task": "$TASK_NAME",
    "task_start_ts": $TASK_START,
    "prefs_file_exists": $PREFS_EXISTS,
    "tor_running": $TOR_RUNNING,
    "preferences": {
        "pdfjs_disabled": $PDFJS_DISABLED,
        "media_standalone_disabled": $MEDIA_STANDALONE_DISABLED,
        "clipboard_events_disabled": $CLIPBOARD_EVENTS_DISABLED,
        "download_dir_prompt": $DOWNLOAD_DIR_PROMPT
    },
    "artifact": {
        "directory_created": $DIRECTORY_CREATED,
        "file_exists": $ARTIFACT_EXISTS,
        "file_is_new": $ARTIFACT_IS_NEW,
        "file_header": "$ARTIFACT_HEADER"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json