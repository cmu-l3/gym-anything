#!/system/bin/sh
# Setup script for record_livestock_weighin_session
# Runs on Android device

echo "=== Setting up Livestock Weigh-in Task ==="

PACKAGE="org.farmos.app"

# Record start time for anti-gaming
date +%s > /sdcard/task_start_time.txt

# Reset app to clean state
echo "Clearing app data..."
am force-stop $PACKAGE
pm clear $PACKAGE
sleep 2

# Grant permissions (required after clear)
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null

# Launch App
echo "Launching farmOS Field Kit..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# Wait for load
sleep 5

# Ensure we are not stuck on a dialog (simulating back/escape just in case)
# Usually fresh install goes to "Let's Get Started" or empty list
# We'll just leave it there for the agent.

echo "=== Setup Complete ==="