#!/system/bin/sh
# Export script for reverse_flight_plan task
# Runs on Android device

echo "=== Exporting Results ==="

# 1. Capture final screenshot (Critical for VLM)
screencap -p /sdcard/task_final.png

# 2. Dump UI Hierarchy (For programmatic verification of text list)
# This allows us to read the waypoint list directly from the screen elements
uiautomator dump /sdcard/ui_dump.xml

# 3. Record end time
date +%s > /sdcard/task_end_time.txt

# 4. Check if app is running
PID=$(pidof com.ds.avare)
if [ -n "$PID" ]; then
    echo "App is running (PID: $PID)"
else
    echo "App is NOT running"
fi

echo "=== Export Complete ==="