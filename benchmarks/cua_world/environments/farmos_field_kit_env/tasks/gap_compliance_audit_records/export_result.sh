#!/system/bin/sh
# Post-task hook: Export farmOS UI state for gap_compliance_audit_records verification

echo "=== Exporting gap_compliance_audit_records state ==="

input keyevent KEYCODE_BACK
sleep 1
input keyevent KEYCODE_BACK
sleep 1
input keyevent KEYCODE_BACK
sleep 2

screencap -p /sdcard/gap_final_screenshot.png 2>/dev/null
echo "Screenshot captured"

uiautomator dump /sdcard/ui_dump_gap.xml 2>/dev/null

if [ -f /sdcard/ui_dump_gap.xml ]; then
    echo "UI dump created: $(wc -c < /sdcard/ui_dump_gap.xml) bytes"
else
    echo "WARNING: UI dump failed"
fi

echo "=== Export completed ==="
