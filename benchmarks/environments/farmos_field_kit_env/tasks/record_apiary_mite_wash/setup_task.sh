#!/system/bin/sh
# Setup script for record_apiary_mite_wash task

echo "=== Setting up record_apiary_mite_wash task ==="

PACKAGE="org.farmos.app"

# Record start timestamp
date +%s > /sdcard/task_start_time.txt

# Force stop to ensure clean state
am force-stop $PACKAGE
sleep 1

# Clear data to remove previous logs (ensures we verify ONLY this task's work)
pm clear $PACKAGE
sleep 2

# Grant necessary permissions
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION

# Launch the app
echo "Launching farmOS Field Kit..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1
sleep 5

# Ensure we are on the main screen (sometimes first run shows dialogs)
# Note: farmOS Field Kit usually starts directly on the Log List screen after clear

echo "=== Setup complete ==="