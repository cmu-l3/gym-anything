#!/system/bin/sh
# Post-task hook: Export UI state for verification

echo "=== Exporting Flight Crew View state for verification ==="

screencap -p /sdcard/final_screenshot.png 2>/dev/null
echo "Screenshot captured to /sdcard/final_screenshot.png"

uiautomator dump /sdcard/ui_dump.xml 2>/dev/null

if [ -f /sdcard/ui_dump.xml ]; then
    echo "UI dump created successfully"
else
    echo "Warning: UI dump failed"
fi

echo "=== Export completed ==="
