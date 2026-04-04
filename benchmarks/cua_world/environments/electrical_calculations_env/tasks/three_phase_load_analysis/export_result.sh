#!/system/bin/sh
# Export script for Three-Phase Load Analysis task

echo "=== Exporting Three-Phase Load Analysis Result ==="

# Capture final screenshot
screencap -p /sdcard/final_screenshot_three_phase_load.png
sleep 1

# Dump UI hierarchy for programmatic verification
uiautomator dump /sdcard/ui_dump_three_phase_load.xml
sleep 1

if [ -f /sdcard/ui_dump_three_phase_load.xml ]; then
    echo "UI dump successful"
    # Also copy to standard location
    cp /sdcard/ui_dump_three_phase_load.xml /sdcard/ui_dump.xml
else
    echo "WARNING: UI dump failed, trying again..."
    uiautomator dump /sdcard/ui_dump.xml
fi

echo "=== Export Complete ==="
