#!/system/bin/sh
echo "=== Exporting disable_analytics_collection results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
screencap -p /sdcard/task_final.png
echo "Screenshot captured."

# 2. Dump UI Hierarchy (to check toggle state if visible)
uiautomator dump /sdcard/ui_dump.xml 2>/dev/null

# 3. Check Shared Preferences for Privacy/Analytics flags
# We look for common keywords in the app's preferences
echo "Checking shared preferences..."
PREFS_OUTPUT=""
if [ -d "/data/data/com.sygic.aura/shared_prefs" ]; then
    # Grep for keys related to analytics/consent
    # specific keys might contain "analytics", "stats", "consent", "improvement"
    # We use run-as if not root, but in this env typically we run as root or have access via shell
    PREFS_OUTPUT=$(grep -iE "analytics|stats|consent|improvement|tracking" /data/data/com.sygic.aura/shared_prefs/*.xml 2>/dev/null)
fi

# 4. Check if app is running
APP_RUNNING=$(pgrep -f "com.sygic.aura" > /dev/null && echo "true" || echo "false")

# 5. Create JSON result
# Note: JSON creation in shell is fragile, using simple format
cat > /sdcard/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "prefs_evidence": "$(echo "$PREFS_OUTPUT" | sed 's/"/\\"/g')",
    "screenshot_path": "/sdcard/task_final.png",
    "ui_dump_path": "/sdcard/ui_dump.xml"
}
EOF

# Set permissions so host can pull
chmod 666 /sdcard/task_result.json
chmod 666 /sdcard/task_final.png
chmod 666 /sdcard/ui_dump.xml 2>/dev/null

echo "=== Export complete ==="