#!/system/bin/sh
# Setup script for analyze_terrain_profile task
echo "=== Setting up Analyze Terrain Profile Task ==="

PACKAGE="com.ds.avare"

# Record start time for anti-gaming
date +%s > /sdcard/task_start_time.txt

# Force stop to ensure clean state
am force-stop $PACKAGE
sleep 2

# Press Home to reset UI stack
input keyevent KEYCODE_HOME
sleep 1

# Ensure permissions are granted
echo "Granting permissions..."
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.READ_EXTERNAL_STORAGE 2>/dev/null
pm grant $PACKAGE android.permission.WRITE_EXTERNAL_STORAGE 2>/dev/null

# Launch Avare to main activity
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# Ensure we are on the map screen (handle any crash recovery dialogs if they appear)
# Tap "Map" or "OK" coordinates if known, but usually simple launch is enough.
# We'll just wait a bit longer to ensure readiness.
sleep 5

echo "=== Setup Complete ==="