#!/system/bin/sh
# Export script for Motor Cable Sizing Calculation task

echo "=== Exporting Motor Cable Sizing Calculation Result ==="

# Capture final screenshot
screencap -p /sdcard/final_screenshot_motor_cable.png
sleep 1

# Dump UI hierarchy
uiautomator dump /sdcard/ui_dump_motor_cable.xml
sleep 1

if [ -f /sdcard/ui_dump_motor_cable.xml ]; then
    echo "UI dump successful"
    cp /sdcard/ui_dump_motor_cable.xml /sdcard/ui_dump.xml
else
    echo "WARNING: UI dump failed, trying fallback..."
    uiautomator dump /sdcard/ui_dump.xml
fi

echo "=== Export Complete ==="
