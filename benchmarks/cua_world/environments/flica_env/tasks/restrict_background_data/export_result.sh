#!/system/bin/sh
# Export script for restrict_background_data task
# Captures final network policy state and screenshot

echo "=== Exporting task results ==="

PACKAGE="com.robert.fcView"
RESULT_JSON="/sdcard/task_result.json"
FINAL_SCREENSHOT="/sdcard/task_final.png"

# 1. Capture Screenshot
screencap -p "$FINAL_SCREENSHOT"

# 2. Get App UID
UID=$(pm list packages -U $PACKAGE | grep -o "uid:[0-9]*" | cut -d: -f2)

# 3. Get Network Policy for this UID
# specific grep to find the line for this app
POLICY_LINE=$(dumpsys netpolicy | grep "uid=$UID" | head -n 1)

# 4. Check UI State (XML Dump)
uiautomator dump /sdcard/ui_dump.xml
UI_CONTENT=""
if [ -f /sdcard/ui_dump.xml ]; then
    UI_CONTENT="dump_created"
fi

# 5. Create JSON Result
# We construct JSON manually in shell
echo "{" > "$RESULT_JSON"
echo "  \"package\": \"$PACKAGE\"," >> "$RESULT_JSON"
echo "  \"uid\": \"$UID\"," >> "$RESULT_JSON"
echo "  \"policy_line\": \"$POLICY_LINE\"," >> "$RESULT_JSON"
echo "  \"screenshot_path\": \"$FINAL_SCREENSHOT\"," >> "$RESULT_JSON"
echo "  \"ui_dump_status\": \"$UI_CONTENT\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Result saved to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="