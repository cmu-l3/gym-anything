#!/system/bin/sh
# Post-task hook: Export UI state for verification

echo "=== Exporting AndroidAPS state for verification ==="

# Dump UI hierarchy to XML file
uiautomator dump /sdcard/ui_dump.xml 2>/dev/null

# Verify the dump was created
if [ -f /sdcard/ui_dump.xml ]; then
    echo "UI dump created successfully"
    ls -la /sdcard/ui_dump.xml
else
    echo "Warning: UI dump failed"
fi

# Also try to capture current activity info
dumpsys activity activities 2>/dev/null | grep -i "androidaps" > /sdcard/activity_state.txt 2>/dev/null

echo "=== Export completed ==="
