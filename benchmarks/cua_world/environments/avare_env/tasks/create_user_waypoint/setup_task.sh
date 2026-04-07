#!/system/bin/sh
echo "=== Setting up create_user_waypoint task ==="

PACKAGE="com.ds.avare"

# 1. Record task start time
date +%s > /sdcard/task_start_time.txt

# 2. Clean up previous state
# Remove existing User Defined Waypoints to ensure a fresh start
echo "Clearing existing UDW files..."
rm -f /sdcard/com.ds.avare/UDW.csv 2>/dev/null
rm -f /data/data/com.ds.avare/files/UDW.csv 2>/dev/null
# Also try standard Android/data path
rm -f /sdcard/Android/data/com.ds.avare/files/UDW.csv 2>/dev/null

# 3. Force stop app to ensure clean launch
echo "Stopping Avare..."
am force-stop $PACKAGE
sleep 2

# 4. Press Home to clear screen
input keyevent KEYCODE_HOME
sleep 1

# 5. Launch Avare
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# 6. Wait for app to load
sleep 8

# 7. Ensure we are on the Map/Main screen (basic heuristic)
# If we are in a menu, press back a few times? 
# Usually fresh launch goes to map. 
# We'll take a screenshot of the initial state.
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="