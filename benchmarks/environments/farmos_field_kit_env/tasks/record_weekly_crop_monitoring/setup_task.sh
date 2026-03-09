#!/system/bin/sh
echo "=== Setting up record_weekly_crop_monitoring task ==="

PACKAGE="org.farmos.app"

# 1. Anti-gaming: Record start time
date +%s > /sdcard/task_start_time.txt

# 2. Ensure clean state (remove any previous logs)
echo "Clearing app data..."
am force-stop $PACKAGE
pm clear $PACKAGE
sleep 2

# 3. Grant permissions (pm clear revokes them)
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.WRITE_EXTERNAL_STORAGE 2>/dev/null
pm grant $PACKAGE android.permission.READ_EXTERNAL_STORAGE 2>/dev/null

# 4. Record initial DB state (should be empty/non-existent)
# We just touch a file to signify 'count 0' logic in verifier
echo "0" > /sdcard/initial_log_count.txt

# 5. Launch the app
echo "Launching farmOS Field Kit..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# 6. Wait for app to load
sleep 8

# 7. Take initial screenshot
screencap -p /sdcard/task_initial_state.png

echo "=== Setup complete ==="