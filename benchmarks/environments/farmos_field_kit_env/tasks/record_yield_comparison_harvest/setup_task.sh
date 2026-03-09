#!/system/bin/sh
echo "=== Setting up record_yield_comparison_harvest task ==="

PACKAGE="org.farmos.app"

# Record task start time for anti-gaming
date +%s > /sdcard/task_start_time.txt

# Force stop to ensure clean state
am force-stop $PACKAGE
sleep 1

# Clear app data to reset database
echo "Clearing app data..."
pm clear $PACKAGE
sleep 2

# Grant permissions (location is often needed by Field Kit)
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null

# Launch the app
echo "Launching farmOS Field Kit..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# Wait for app to load (simple sleep since we can't easily poll window state in minimal shell)
sleep 8

# Ensure we are not on a crash dialog or permission prompt (simple tap to dismiss if any)
# Tapping center of screen just in case
input tap 540 1200 2>/dev/null

echo "=== Task setup complete ==="