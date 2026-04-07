#!/system/bin/sh
# Export script for analyze_terrain_profile task

echo "=== Exporting Task Result ==="

PACKAGE="com.ds.avare"
RESULT_PATH="/sdcard/task_result.json"
SCREENSHOT_PATH="/sdcard/final_screenshot.png"
UI_DUMP_PATH="/sdcard/ui_dump.xml"

# 1. Capture Final Screenshot (Critical for VLM)
screencap -p "$SCREENSHOT_PATH"
echo "Screenshot captured."

# 2. Dump UI Hierarchy (Text verification)
uiautomator dump "$UI_DUMP_PATH" 2>/dev/null
echo "UI dump created."

# 3. Check if App is Running
if pidof "$PACKAGE" > /dev/null; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# 4. Check internal plan file (Anti-gaming / Secondary check)
# Avare stores state in /data/data/com.ds.avare/shared_prefs/ or internal DBs
# We try to grep the UI dump for key text as a proxy for internal state if root is restricted
PLAN_VISIBLE="false"
if grep -q "KSMF" "$UI_DUMP_PATH" && grep -q "KRNO" "$UI_DUMP_PATH"; then
    PLAN_VISIBLE="true"
fi

PROFILE_VISIBLE="false"
if grep -i "Profile" "$UI_DUMP_PATH" || grep -i "Elevation" "$UI_DUMP_PATH"; then
    # Weak check, VLM is primary
    PROFILE_VISIBLE="true"
fi

# 5. Create Result JSON
# Note: Using simple echo for JSON construction to avoid dependency issues on Android
echo "{" > "$RESULT_PATH"
echo "  \"app_running\": $APP_RUNNING," >> "$RESULT_PATH"
echo "  \"plan_text_visible\": $PLAN_VISIBLE," >> "$RESULT_PATH"
echo "  \"profile_text_visible\": $PROFILE_VISIBLE," >> "$RESULT_PATH"
echo "  \"timestamp\": $(date +%s)" >> "$RESULT_PATH"
echo "}" >> "$RESULT_PATH"

echo "Result JSON saved to $RESULT_PATH"
cat "$RESULT_PATH"

echo "=== Export Complete ==="