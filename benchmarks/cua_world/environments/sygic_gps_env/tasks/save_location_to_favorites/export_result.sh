#!/system/bin/sh
echo "=== Exporting save_location_to_favorites results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
screencap -p /sdcard/task_final.png

# Dump UI hierarchy (useful for text verification)
# Note: Sygic map is OpenGL, but menus/lists are often Android Views
uiautomator dump /sdcard/ui_dump.xml 2>/dev/null || true

# Check if UI dump was created
UI_DUMP_EXISTS="false"
if [ -f /sdcard/ui_dump.xml ]; then
    UI_DUMP_EXISTS="true"
fi

# Create result JSON
# We use a temporary file approach to ensure atomic write if possible, 
# though on Android shell mktemp might behave differently. 
# We'll just write directly.

cat > /sdcard/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "ui_dump_exists": $UI_DUMP_EXISTS,
    "screenshot_path": "/sdcard/task_final.png",
    "ui_dump_path": "/sdcard/ui_dump.xml"
}
EOF

echo "Result saved to /sdcard/task_result.json"
echo "=== Export complete ==="