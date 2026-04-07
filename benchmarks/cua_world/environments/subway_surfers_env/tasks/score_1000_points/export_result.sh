#!/system/bin/sh
# Post-task hook: Export game state for verification
# This runs after the agent has completed its actions

echo "=== Exporting Subway Surfers game state for verification ==="

# Take a screenshot of the current state (useful for debugging)
screencap -p /sdcard/final_screenshot.png 2>/dev/null
echo "Screenshot captured to /sdcard/final_screenshot.png"

# Dump UI hierarchy to XML file
# This should capture the score display from either:
# 1. In-game score (top of screen during gameplay)
# 2. Game over screen score
uiautomator dump /sdcard/ui_dump.xml 2>/dev/null

# Verify the dump was created
if [ -f /sdcard/ui_dump.xml ]; then
    echo "UI dump created successfully"
    ls -la /sdcard/ui_dump.xml

    # Show some content for debugging
    echo "UI dump preview:"
    head -c 2000 /sdcard/ui_dump.xml 2>/dev/null
else
    echo "Warning: UI dump failed"
fi

# Try to get any visible score information from the UI
# Search for common score-related patterns
echo ""
echo "Looking for score patterns in UI dump..."
if [ -f /sdcard/ui_dump.xml ]; then
    # Extract text attributes that might contain score
    grep -o 'text="[^"]*"' /sdcard/ui_dump.xml 2>/dev/null | head -20
fi

echo ""
echo "=== Export completed ==="
