#!/system/bin/sh
# Post-task hook: Export UI state for verification
# This runs after the agent has completed its actions

echo "=== Exporting calculator state for verification ==="

# Dump UI hierarchy to XML file
uiautomator dump /sdcard/ui_dump.xml 2>/dev/null

# Verify the dump was created
if [ -f /sdcard/ui_dump.xml ]; then
    echo "UI dump created successfully"
    ls -la /sdcard/ui_dump.xml
else
    echo "Warning: UI dump failed"
fi

echo "=== Export completed ==="
