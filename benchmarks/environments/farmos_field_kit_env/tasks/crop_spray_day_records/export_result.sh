#!/system/bin/sh
# Post-task hook: Export farmOS UI state for crop_spray_day_records verification

echo "=== Exporting crop_spray_day_records state ==="

# Press back multiple times to exit any open form and return to Tasks list
input keyevent KEYCODE_BACK
sleep 1
input keyevent KEYCODE_BACK
sleep 1
input keyevent KEYCODE_BACK
sleep 2

# Take final screenshot
screencap -p /sdcard/crop_spray_final_screenshot.png 2>/dev/null
echo "Screenshot captured"

# Dump UI hierarchy for verification
uiautomator dump /sdcard/ui_dump_crop_spray.xml 2>/dev/null

if [ -f /sdcard/ui_dump_crop_spray.xml ]; then
    echo "UI dump created: $(wc -c < /sdcard/ui_dump_crop_spray.xml) bytes"
else
    echo "WARNING: UI dump failed"
fi

echo "=== Export completed ==="
