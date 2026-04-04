#!/system/bin/sh
# Setup script for record_silo_gas_safety_check
# Runs inside the Android environment

echo "=== Setting up Silo Gas Safety Check Task ==="

PACKAGE="org.farmos.app"

# 1. Force stop and clear app data to ensure a clean starting state
echo "Clearing app data..."
am force-stop $PACKAGE
pm clear $PACKAGE
sleep 2

# 2. Grant necessary permissions (Location is required by the app)
echo "Granting permissions..."
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null

# 3. Launch the application
echo "Launching farmOS Field Kit..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 4. Ensure we are on the main screen (Tasks list)
# The first launch might show a splash screen or empty list.
# We'll send a Back key just in case a dialog is open, then ensure we are focused.
input keyevent KEYCODE_BACK
sleep 1

# Record start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

echo "=== Setup Complete ==="