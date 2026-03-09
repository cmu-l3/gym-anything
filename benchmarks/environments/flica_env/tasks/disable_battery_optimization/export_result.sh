#!/system/bin/sh
echo "=== Exporting disable_battery_optimization results ==="

PACKAGE="com.robert.fcView"
RESULT_FILE="/sdcard/task_result.json"

# 1. CAPTURE FINAL SCREENSHOT
screencap -p /sdcard/task_final.png

# 2. CHECK SYSTEM STATE (Ground Truth)

# Check Device Idle Whitelist (Primary Signal)
# This lists packages that ignore battery optimizations
WHITELIST_OUTPUT=$(dumpsys deviceidle whitelist)
if echo "$WHITELIST_OUTPUT" | grep -q "$PACKAGE"; then
    IS_WHITELISTED="true"
else
    IS_WHITELISTED="false"
fi

# Check App Ops (Secondary Signal)
# Checks if background execution is explicitly allowed
APPOPS_OUTPUT=$(cmd appops get $PACKAGE RUN_ANY_IN_BACKGROUND 2>/dev/null || echo "")
if echo "$APPOPS_OUTPUT" | grep -qi "allow"; then
    BG_ALLOWED="true"
else
    BG_ALLOWED="false"
fi

# Check Recent Tasks (Trajectory Signal)
# Did they actually open Settings?
RECENTS_OUTPUT=$(dumpsys activity recents | head -n 50)
if echo "$RECENTS_OUTPUT" | grep -qi "com.android.settings"; then
    SETTINGS_ACCESSED="true"
else
    SETTINGS_ACCESSED="false"
fi

# 3. GET TIMESTAMPS
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 4. GENERATE JSON RESULT
# Writing JSON manually since Android shell might not have jq
echo "{" > "$RESULT_FILE"
echo "  \"task_start\": $TASK_START," >> "$RESULT_FILE"
echo "  \"task_end\": $CURRENT_TIME," >> "$RESULT_FILE"
echo "  \"is_whitelisted\": $IS_WHITELISTED," >> "$RESULT_FILE"
echo "  \"bg_ops_allowed\": $BG_ALLOWED," >> "$RESULT_FILE"
echo "  \"settings_accessed\": $SETTINGS_ACCESSED," >> "$RESULT_FILE"
echo "  \"package_name\": \"$PACKAGE\"" >> "$RESULT_FILE"
echo "}" >> "$RESULT_FILE"

echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="