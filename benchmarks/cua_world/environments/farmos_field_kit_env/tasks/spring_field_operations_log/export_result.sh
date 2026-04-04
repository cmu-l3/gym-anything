#!/system/bin/sh
# Post-task hook: Export farmOS UI state for spring_field_operations_log verification

echo "=== Exporting spring_field_operations_log state ==="

input keyevent KEYCODE_BACK
sleep 1
input keyevent KEYCODE_BACK
sleep 1
input keyevent KEYCODE_BACK
sleep 2

screencap -p /sdcard/spring_final_screenshot.png 2>/dev/null
echo "Screenshot captured"

uiautomator dump /sdcard/ui_dump_spring.xml 2>/dev/null

if [ -f /sdcard/ui_dump_spring.xml ]; then
    echo "UI dump created: $(wc -c < /sdcard/ui_dump_spring.xml) bytes"
else
    echo "WARNING: UI dump failed"
fi

echo "=== Export completed ==="
