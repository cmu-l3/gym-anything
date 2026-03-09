#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting A-B Loop Practice Result ==="

# Initialize result variables
LOOP_STATE="unknown"
LOOP_START=""
LOOP_END=""
CONFIRMATION_FOUND="false"

# Check if agent created confirmation file
if [ -f /tmp/ab_loop_confirmation.txt ]; then
    echo "✅ Loop confirmation file found"
    CONFIRMATION_FOUND="true"
    
    # Parse confirmation file for loop parameters
    if grep -iq "start" /tmp/ab_loop_confirmation.txt; then
        LOOP_START=$(grep -i "start" /tmp/ab_loop_confirmation.txt | grep -oP '\d+\.?\d*' | head -1)
        echo "Loop start from confirmation: ${LOOP_START}s"
    fi
    
    if grep -iq "end" /tmp/ab_loop_confirmation.txt; then
        LOOP_END=$(grep -i "end" /tmp/ab_loop_confirmation.txt | grep -oP '\d+\.?\d*' | head -1)
        echo "Loop end from confirmation: ${LOOP_END}s"
    fi
    
    # Copy confirmation file for verification
    cp /tmp/ab_loop_confirmation.txt /tmp/vlc_ab_loop_confirmation.txt
    
    echo "--- Confirmation File Content ---"
    cat /tmp/ab_loop_confirmation.txt
    echo "---------------------------------"
else
    echo "⚠️ Loop confirmation file not found at /tmp/ab_loop_confirmation.txt"
fi

# Try to detect loop state from VLC if running
if is_vlc_running; then
    echo "VLC is running, attempting to capture state..."
    
    # Take screenshot to capture any loop indicators on UI
    SCREENSHOT_PATH="/tmp/vlc_ab_loop_screenshot.png"
    su - ga -c "DISPLAY=:1 import -window root '$SCREENSHOT_PATH'" 2>/dev/null || \
    su - ga -c "DISPLAY=:1 scrot '$SCREENSHOT_PATH'" 2>/dev/null || \
    echo "⚠️ Could not capture screenshot"
    
    if [ -f "$SCREENSHOT_PATH" ]; then
        echo "✅ Screenshot captured: $SCREENSHOT_PATH"
    fi
fi

# Check VLC config for any loop-related settings
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    echo "Checking VLC config for loop settings..."
    
    # Check for loop/repeat settings
    if grep -q "loop\|repeat" "$VLC_RC"; then
        echo "Loop-related config found:"
        grep "loop\|repeat" "$VLC_RC" | head -5
    fi
    
    # Copy config for verification
    cp "$VLC_RC" /tmp/vlc_ab_loop_config.txt
fi

# Calculate loop duration if both start and end are available
LOOP_DURATION=""
if [ -n "$LOOP_START" ] && [ -n "$LOOP_END" ]; then
    LOOP_DURATION=$(echo "$LOOP_END - $LOOP_START" | bc 2>/dev/null || echo "")
    if [ -n "$LOOP_DURATION" ]; then
        echo "Calculated loop duration: ${LOOP_DURATION}s"
    fi
fi

# Close VLC gracefully
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force closing VLC..."
        kill_vlc ga
        sleep 1
    fi
fi

# Close any text editors that might be open
pkill -f "gedit.*dialogue_segment" 2>/dev/null || true
pkill -f "mousepad.*dialogue_segment" 2>/dev/null || true
pkill -f "xed.*dialogue_segment" 2>/dev/null || true

# Create comprehensive result JSON
cat > /tmp/vlc_ab_loop_result.json <<EOF
{
    "confirmation_found": $CONFIRMATION_FOUND,
    "loop_start": "${LOOP_START:-null}",
    "loop_end": "${LOOP_END:-null}",
    "loop_duration": "${LOOP_DURATION:-null}",
    "screenshot_captured": $([ -f "$SCREENSHOT_PATH" ] && echo "true" || echo "false"),
    "config_checked": $([ -f "$VLC_RC" ] && echo "true" || echo "false")
}
EOF

echo "✅ Result JSON created:"
cat /tmp/vlc_ab_loop_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_ab_loop_completed.txt
echo "A-B loop setup task completed" >> /tmp/vlc_ab_loop_completed.txt
echo "Confirmation found: $CONFIRMATION_FOUND" >> /tmp/vlc_ab_loop_completed.txt
if [ -n "$LOOP_START" ] && [ -n "$LOOP_END" ]; then
    echo "Loop parameters: ${LOOP_START}s - ${LOOP_END}s (${LOOP_DURATION}s)" >> /tmp/vlc_ab_loop_completed.txt
fi

echo ""
echo "=== Export Complete ==="
echo "Files created:"
echo "  - /tmp/vlc_ab_loop_result.json (result summary)"
echo "  - /tmp/vlc_ab_loop_confirmation.txt (agent's confirmation)"
echo "  - /tmp/vlc_ab_loop_completed.txt (completion marker)"
echo "  - /tmp/vlc_ab_loop_screenshot.png (UI screenshot, if captured)"