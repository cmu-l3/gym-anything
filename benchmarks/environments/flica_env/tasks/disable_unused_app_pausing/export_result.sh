#!/system/bin/sh
# Export result for disable_unused_app_pausing
# Checks the autoRevokePermissionsMode status

echo "=== Exporting results ==="

PACKAGE="com.robert.fcView"
RESULT_JSON="/sdcard/task_result.json"

# 1. Capture Final Screenshot
screencap -p /sdcard/final_screenshot.png 2>/dev/null

# 2. Check Task End Time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 3. Query System State
# We look for autoRevokePermissionsMode: [0-2]
# 0 = Default (Revoke ON)
# 1 = Allowed (Revoke ON)
# 2 = Ignored (Revoke OFF) -> TARGET
DUMP_OUTPUT=$(dumpsys package $PACKAGE | grep "autoRevokePermissionsMode" | tr -d ' ')
# Extract just the number
MODE_VAL=$(echo "$DUMP_OUTPUT" | sed 's/autoRevokePermissionsMode://')

if [ -z "$MODE_VAL" ]; then
    MODE_VAL="-1"
fi

echo "Final Mode Value: $MODE_VAL"

# 4. Check if Settings app was used (Anti-gaming: did they actually use UI?)
SETTINGS_USED="false"
# Simple check: is Settings in recent tasks or was it top activity recently?
# We can dump the activity stack
STACK_DUMP=$(dumpsys activity activities | grep "com.android.settings")
if [ -n "$STACK_DUMP" ]; then
    SETTINGS_USED="true"
fi

# 5. Create JSON
# Note: creating JSON in shell is fragile, handle carefully
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"task_end\": $TASK_END," >> "$RESULT_JSON"
echo "  \"package\": \"$PACKAGE\"," >> "$RESULT_JSON"
echo "  \"auto_revoke_mode\": $MODE_VAL," >> "$RESULT_JSON"
echo "  \"settings_activity_detected\": $SETTINGS_USED," >> "$RESULT_JSON"
echo "  \"screenshot_path\": \"/sdcard/final_screenshot.png\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Result saved to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="