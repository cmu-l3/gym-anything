#!/bin/bash
# Export script for Virtual Coaching Session task

echo "=== Exporting Virtual Coaching Session Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

# Take final screenshot
take_screenshot /tmp/coaching_task_end.png

# Get task start timestamp
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# --- Check config guide file ---
GUIDE_FILE="/home/ga/Desktop/coaching_session_config.txt"
REPORT_EXISTS=0
REPORT_SIZE=0
REPORT_MTIME=0

if [ -f "$GUIDE_FILE" ]; then
    REPORT_EXISTS=1
    REPORT_SIZE=$(wc -c < "$GUIDE_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$GUIDE_FILE" 2>/dev/null || echo "0")
fi

# --- Check guide content for procedure vocabulary ---
HAS_URL=0
HAS_BACKGROUND=0
HAS_MUTED=0
HAS_COACHING=0
HAS_QUALITY=0

if [ -f "$GUIDE_FILE" ]; then
    grep -qiE "localhost:8080|FitCoach|fitcoach|8080/Fit" "$GUIDE_FILE" 2>/dev/null && HAS_URL=1
    # 'virtual background' vocabulary only discoverable by using Jitsi's background feature
    grep -qiE "virtual|background|blur|replace.*background|background.*blur" "$GUIDE_FILE" 2>/dev/null && HAS_BACKGROUND=1
    # Mute policy vocabulary: only appears after configuring the everyone-starts-muted setting
    grep -qiE "muted|everyone.*muted|start.*muted|microphone|participants.*start" "$GUIDE_FILE" 2>/dev/null && HAS_MUTED=1
    # Coaching vocabulary (validates the professional context)
    grep -qiE "coach|fitness|instructor|session|workout|training" "$GUIDE_FILE" 2>/dev/null && HAS_COACHING=1
    # Video quality vocabulary: appears in Jitsi's quality settings dialog
    grep -qiE "quality|definition|HD|high definition|video.*quality|resolution" "$GUIDE_FILE" 2>/dev/null && HAS_QUALITY=1
fi

# --- Write result JSON ---
cat > /tmp/virtual_coaching_session_result.json << EOF
{
    "task_start": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "has_url": $HAS_URL,
    "has_background": $HAS_BACKGROUND,
    "has_muted": $HAS_MUTED,
    "has_coaching": $HAS_COACHING,
    "has_quality": $HAS_QUALITY,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result written to /tmp/virtual_coaching_session_result.json"
echo "=== Export Complete ==="
