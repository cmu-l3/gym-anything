#!/system/bin/sh
# Post-task hook: Export UI state for verification

echo "=== Exporting Electrical Calculations state for verification ==="

# Take screenshot
screencap -p /sdcard/final_screenshot.png 2>/dev/null
echo "Screenshot captured to /sdcard/final_screenshot.png"

# Dump UI hierarchy for verification
uiautomator dump /sdcard/ui_dump.xml 2>/dev/null

if [ -f /sdcard/ui_dump.xml ]; then
    echo "UI dump created successfully"
else
    echo "Warning: UI dump failed"
fi

echo "=== Export completed ==="
