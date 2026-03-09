#!/system/bin/sh
# Export script for Three-Phase Line-to-Phase Conversions task

echo "=== Exporting Three-Phase Line-to-Phase Conversions Result ==="

# Capture final screenshot
screencap -p /sdcard/final_screenshot_lp_conv.png
sleep 1

# Dump UI hierarchy
uiautomator dump /sdcard/ui_dump_lp_conv.xml
sleep 1

if [ -f /sdcard/ui_dump_lp_conv.xml ]; then
    echo "UI dump successful"
    cp /sdcard/ui_dump_lp_conv.xml /sdcard/ui_dump.xml
else
    echo "WARNING: UI dump failed, trying fallback..."
    uiautomator dump /sdcard/ui_dump.xml
fi

echo "=== Export Complete ==="
