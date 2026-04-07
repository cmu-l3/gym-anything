#!/system/bin/sh
# Export script for Three-Phase Motor Feeder Assessment task

echo "=== Exporting Three-Phase Motor Feeder Assessment Result ==="

# Capture final screenshot
screencap -p /sdcard/final_screenshot_motor_feeder.png
sleep 1

# Dump UI hierarchy for programmatic verification
uiautomator dump /sdcard/ui_dump_motor_feeder.xml
sleep 1

if [ -f /sdcard/ui_dump_motor_feeder.xml ]; then
    echo "UI dump successful"
    # Also copy to standard location
    cp /sdcard/ui_dump_motor_feeder.xml /sdcard/ui_dump.xml
else
    echo "WARNING: UI dump failed, trying again..."
    uiautomator dump /sdcard/ui_dump.xml
fi

echo "=== Export Complete ==="
