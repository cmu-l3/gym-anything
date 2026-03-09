#!/system/bin/sh
# Export script for record_daily_egg_harvest
# Captures UI state and visual evidence

echo "=== Exporting task results ==="

# 1. Capture final screenshot (Primary visual evidence of completion)
screencap -p /sdcard/task_final.png

# 2. Dump UI Hierarchy (Primary programmatic evidence of final state)
# This allows us to check if the log exists in the list without VLM
uiautomator dump /sdcard/ui_dump.xml

# 3. Check for specific text on screen to create a simple summary JSON
# (This helps if XML parsing on the host side is brittle)
echo "Analyzing UI state..."

# Check if Title exists on screen
if grep -q "Daily Egg Collection - Red Barn" /sdcard/ui_dump.xml; then
    TITLE_FOUND="true"
else
    TITLE_FOUND="false"
fi

# Check if "Harvest" type indicator exists
# Note: farmOS list usually shows the type in small text
if grep -q "Harvest" /sdcard/ui_dump.xml; then
    TYPE_FOUND="true"
else
    TYPE_FOUND="false"
fi

# Create result JSON
cat > /sdcard/task_result.json <<EOF
{
    "timestamp": "$(date)",
    "title_found_in_ui": $TITLE_FOUND,
    "type_found_in_ui": $TYPE_FOUND,
    "ui_dump_path": "/sdcard/ui_dump.xml",
    "screenshot_path": "/sdcard/task_final.png"
}
EOF

echo "Result exported to /sdcard/task_result.json"
cat /sdcard/task_result.json
echo "=== Export complete ==="