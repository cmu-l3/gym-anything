#!/system/bin/sh
set -e
echo "=== Setting up Amend Flight Plan Task ==="

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

PACKAGE="com.ds.avare"

# Clean up any existing GPX files to prevent false positives
# We look in common export locations
rm -f /sdcard/*.gpx 2>/dev/null || true
rm -f /sdcard/Download/*.gpx 2>/dev/null || true
rm -f /sdcard/Documents/*.gpx 2>/dev/null || true

# Force stop Avare to ensure clean state
am force-stop $PACKAGE
sleep 2

# Launch Avare
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# Ensure we are on the main screen (sometimes it opens to last used)
# We can't easily force specific tab via intent, but a restart usually helps.
# The agent is responsible for navigating to the 'Plan' tab.

# Take initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Task setup complete ==="