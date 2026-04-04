#!/system/bin/sh
# Setup script for record_biosecurity_visitor_entry task
# Clears app data to ensure a clean state and launches the app.

echo "=== Setting up Biosecurity Log Task ==="

PACKAGE="org.farmos.app"

# 1. Clean environment
echo "Stopping and clearing app data..."
am force-stop $PACKAGE
pm clear $PACKAGE
sleep 2

# 2. Grant permissions (Location is needed for the map view to work without prompts)
echo "Granting permissions..."
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null

# 3. Launch App
echo "Launching farmOS Field Kit..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# 4. Wait for load
sleep 5

# 5. Ensure we are on the main screen (sometimes it needs a second launch or back press)
# Check if we are at the launcher (home screen) which means crash, or stuck.
# We'll just assume monkey worked.

# Record start time for verification
date +%s > /sdcard/task_start_time.txt

echo "=== Setup Complete ==="