#!/system/bin/sh
echo "=== Exporting Star-Delta Conversion Results ==="

PACKAGE="com.hsn.electricalcalculations"
RESULT_JSON="/sdcard/task_result.json"

# 1. Capture Final Screenshot
screencap -p /sdcard/task_final.png

# 2. Dump UI Hierarchy (XML) - useful for text scraping if VLM fails
uiautomator dump /sdcard/ui_dump.xml > /dev/null 2>&1

# 3. Check if App is in Foreground
APP_IN_FOREGROUND="false"
if dumpsys window | grep -q "mCurrentFocus.*$PACKAGE"; then
    APP_IN_FOREGROUND="true"
fi

# 4. Get Timestamps
START_TIME=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(date +%s)

# 5. Create JSON Result
# We construct JSON manually using echo since jq might not be available on Android shell
echo "{" > $RESULT_JSON
echo "  \"app_in_foreground\": $APP_IN_FOREGROUND," >> $RESULT_JSON
echo "  \"start_time\": $START_TIME," >> $RESULT_JSON
echo "  \"end_time\": $END_TIME," >> $RESULT_JSON
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"," >> $RESULT_JSON
echo "  \"ui_dump_path\": \"/sdcard/ui_dump.xml\"" >> $RESULT_JSON
echo "}" >> $RESULT_JSON

# Set permissions to ensure host can read it
chmod 666 $RESULT_JSON 2>/dev/null
chmod 666 /sdcard/task_final.png 2>/dev/null
chmod 666 /sdcard/ui_dump.xml 2>/dev/null

echo "=== Export complete ==="
cat $RESULT_JSON