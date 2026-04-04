#!/system/bin/sh
# Setup script for record_wool_clip_harvest task
# Clears app data to ensure a clean state and launches the app.

echo "=== Setting up record_wool_clip_harvest task ==="

PACKAGE="org.farmos.app"

# 1. Clean environment
echo "Clearing app data..."
am force-stop $PACKAGE
pm clear $PACKAGE
sleep 2

# 2. Grant necessary permissions (Location is needed for the map view to work without prompts)
echo "Granting permissions..."
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null

# 3. Launch the app
echo "Launching farmOS Field Kit..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# 4. Wait for app to load
sleep 5

# 5. Ensure we are not on the splash screen
# (Optional: check focus, but sleep is usually sufficient for this lightweight app)

# 6. Create a timestamp for anti-gaming checks
date +%s > /sdcard/task_start_time.txt

echo "=== Setup complete ==="