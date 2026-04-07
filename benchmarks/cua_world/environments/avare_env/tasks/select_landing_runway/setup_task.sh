#!/system/bin/sh
# Setup script for select_landing_runway task
# Validates environment and prepares Avare

echo "=== Setting up select_landing_runway task ==="

PACKAGE="com.ds.avare"
REPORT_FILE="/sdcard/runway_report.txt"

# 1. Clean up previous task artifacts
rm -f "$REPORT_FILE" 2>/dev/null
echo "Cleaned up old report file"

# 2. Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# 3. Ensure Avare is in a clean state (Force stop and clear cache if needed, but keep data)
am force-stop $PACKAGE
sleep 2

# 4. Launch Avare to the main activity
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# 5. Ensure we are on the Map/Main screen
# (Optional) We could inject key events to clear menus if we suspected a dirty state,
# but force-stop usually resets UI stack to main.

# 6. Capture initial state screenshot
screencap -p /sdcard/task_initial.png 2>/dev/null

echo "=== Task setup complete ==="