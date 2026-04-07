#!/system/bin/sh
# Setup script for configure_traffic_alert_thresholds
# Runs on the Android device

echo "=== Setting up Traffic Alert Configuration Task ==="

# 1. Record start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# 2. Force stop Avare to ensure clean state
PACKAGE="com.ds.avare"
am force-stop $PACKAGE
sleep 2

# 3. Ensure Avare is installed and permissions are granted
# (Standard setup handles installation, we just double check permissions)
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null

# 4. Optional: Reset preferences to ensure agent does work?
# Clearing all data might require re-downloading DBs which is too slow.
# We will rely on checking the file modification time and the specific values.

# 5. Launch Avare
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# 6. Wait for app to load
sleep 10

# 7. Take initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="