#!/system/bin/sh
echo "=== Setting up Mushroom Log Inoculation Task ==="

# Record task start time for anti-gaming
date +%s > /sdcard/task_start_time.txt

PACKAGE="org.farmos.app"

# 1. Clean Slate: Force stop and clear data
echo "Clearing app data..."
am force-stop $PACKAGE
pm clear $PACKAGE
sleep 2

# 2. Permissions: Grant necessary permissions
echo "Granting permissions..."
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null

# 3. Launch App: Start the application
echo "Launching farmOS Field Kit..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# 4. Wait for App to Load
sleep 5

# 5. Verify App is Foreground
# Simple check using dumpsys (optional but good for debugging)
if dumpsys window | grep -q "mCurrentFocus.*org.farmos.app"; then
    echo "App launched successfully."
else
    echo "WARNING: App might not be in focus."
    # Try launching one more time just in case
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 3
fi

echo "=== Setup Complete ==="