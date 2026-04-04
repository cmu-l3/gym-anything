#!/system/bin/sh
# Setup script for record_vineyard_maturity_sampling task.
# Ensures a clean state for farmOS Field Kit.

echo "=== Setting up record_vineyard_maturity_sampling task ==="

PACKAGE="org.farmos.app"

# Record task start time
date +%s > /sdcard/task_start_time.txt

# Force stop the app to ensure fresh start
am force-stop $PACKAGE
sleep 1

# Clear app data to remove any previous logs (ensures clean DB for verification)
# NOTE: In a persistent scenario, we wouldn't do this, but for this task 
# we want to verify ONLY the log created during the session.
pm clear $PACKAGE
sleep 2

# Grant necessary permissions
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null

# Launch the application
echo "Launching farmOS Field Kit..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# Wait for app to initialize
sleep 5

# Ensure we are at the main activity (Tasks list)
# We might see the "Welcome" or empty state.
echo "Setup complete. App should be open."