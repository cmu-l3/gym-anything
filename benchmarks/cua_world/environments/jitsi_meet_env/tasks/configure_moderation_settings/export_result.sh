#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting: Configure Moderation Settings ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ELAPSED=$((TASK_END - TASK_START))

# ── Take final screenshot ────────────────────────────────────────────────────
take_screenshot /tmp/task_final_state.png
sleep 1

# ── Programmatic Check 1: Firefox is running ─────────────────────────────────
FIREFOX_RUNNING="false"
if pgrep -f firefox > /dev/null 2>&1; then
    FIREFOX_RUNNING="true"
fi

# ── Programmatic Check 2: Meeting was joined ────────────────────────────────
# Check window title - if still on pre-join, title typically shows "Jitsi Meet"
# If in a meeting, title typically shows the room name
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
echo "Active window title: $WINDOW_TITLE"

MEETING_JOINED="false"
if echo "$WINDOW_TITLE" | grep -qi "CompanyAllHands"; then
    MEETING_JOINED="true"
fi

# ── Programmatic Check 3: Initial vs final state differ ─────────────────────
STATE_CHANGED="false"
if [ -f /tmp/task_initial_state.png ] && [ -f /tmp/task_final_state.png ]; then
    INITIAL_HASH=$(identify -format "%#" /tmp/task_initial_state.png 2>/dev/null || echo "a")
    FINAL_HASH=$(identify -format "%#" /tmp/task_final_state.png 2>/dev/null || echo "b")
    if [ "$INITIAL_HASH" != "$FINAL_HASH" ]; then
        STATE_CHANGED="true"
    fi
fi

# ── Create JSON result ───────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "elapsed_seconds": $ELAPSED,
    "firefox_running": $FIREFOX_RUNNING,
    "window_title": "$WINDOW_TITLE",
    "meeting_joined": $MEETING_JOINED,
    "state_changed": $STATE_CHANGED,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="