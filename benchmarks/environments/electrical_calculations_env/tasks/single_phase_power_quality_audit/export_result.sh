#!/system/bin/sh
# Export script for Single-Phase Power Quality Audit task

echo "=== Exporting Single-Phase Power Quality Audit Result ==="

# Capture final screenshot
screencap -p /sdcard/final_screenshot_sp_power.png
sleep 1

# Dump UI hierarchy
uiautomator dump /sdcard/ui_dump_sp_power.xml
sleep 1

if [ -f /sdcard/ui_dump_sp_power.xml ]; then
    echo "UI dump successful"
    cp /sdcard/ui_dump_sp_power.xml /sdcard/ui_dump.xml
else
    echo "WARNING: UI dump failed, trying fallback..."
    uiautomator dump /sdcard/ui_dump.xml
fi

echo "=== Export Complete ==="
