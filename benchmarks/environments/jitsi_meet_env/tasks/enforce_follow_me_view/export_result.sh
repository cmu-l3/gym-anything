#!/bin/bash
set -e

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Capture final visual state
take_screenshot /tmp/task_final.png

# Retrieve task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check if Firefox is running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# -----------------------------------------------------------------------------
# JAVASCRIPT STATE EXTRACTION
# -----------------------------------------------------------------------------
# We need to query the internal Redux store of Jitsi Meet to see if "Follow Me" is enabled.
# Since we cannot directly attach to the JS context, we use the Console Hack:
# 1. Open Web Console (Ctrl+Shift+K)
# 2. Type JS that changes the window title to the result
# 3. Read the window title via wmctrl/xdotool
# 4. Revert title (optional)

FOLLOW_ME_ENABLED="false"
DETECTION_METHOD="none"

if [ "$APP_RUNNING" = "true" ]; then
    echo "Attempting to extract state via Firefox Console..."
    
    focus_firefox
    sleep 1
    
    # Open Web Console
    DISPLAY=:1 xdotool key ctrl+shift+k
    sleep 2
    
    # Clear console (Ctrl+L doesn't work in all devtools, but we just type)
    # Payload: Check store state, prefix title with "STATE_RES:"
    # We use a distinct prefix to filter out normal titles.
    JS_PAYLOAD="try { var state = APP.store.getState()['features/base/conference'].followMeEnabled; document.title = 'STATE_RES:' + state; } catch(e) { document.title = 'STATE_RES:ERROR'; }"
    
    DISPLAY=:1 xdotool type --delay 10 "$JS_PAYLOAD"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 2
    
    # Read Window Title
    # wmctrl -l lists windows. We grep for our prefix.
    # Expected output line: "0x00c00003  1 ga-desktop STATE_RES:true - Mozilla Firefox"
    WINDOW_LINE=$(DISPLAY=:1 wmctrl -l | grep "STATE_RES:" || true)
    
    if [ -n "$WINDOW_LINE" ]; then
        echo "Found State Line: $WINDOW_LINE"
        if echo "$WINDOW_LINE" | grep -q "STATE_RES:true"; then
            FOLLOW_ME_ENABLED="true"
            DETECTION_METHOD="js_injection"
        elif echo "$WINDOW_LINE" | grep -q "STATE_RES:false"; then
            FOLLOW_ME_ENABLED="false"
            DETECTION_METHOD="js_injection"
        else
            echo "WARNING: Javascript execution returned error or unexpected value."
        fi
    else
        echo "WARNING: Could not find window with injected title."
    fi
    
    # Close console (F12 often toggles devtools)
    DISPLAY=:1 xdotool key F12
fi

# -----------------------------------------------------------------------------
# EXPORT JSON
# -----------------------------------------------------------------------------

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "follow_me_enabled": $FOLLOW_ME_ENABLED,
    "detection_method": "$DETECTION_METHOD",
    "screenshot_path": "/tmp/task_final.png"
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