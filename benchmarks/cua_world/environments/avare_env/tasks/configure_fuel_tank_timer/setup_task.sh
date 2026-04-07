#!/system/bin/sh
# Setup script for configure_fuel_tank_timer task
# Ensures Avare is running on the map screen with default settings (if possible)

echo "=== Setting up configure_fuel_tank_timer task ==="

PACKAGE="com.ds.avare"

# 1. Force stop to ensure clean state
am force-stop $PACKAGE
sleep 2

# 2. Record start time for anti-gaming
date +%s > /sdcard/task_start_time.txt

# 3. Optional: Reset specific preferences if accessible
# We try to clear preferences to ensure the timer isn't already there.
# Note: clearing all data (pm clear) deletes maps, so we avoid that.
# Instead, we just rely on the default state usually not having the timer.
# If we had root access to /data/data, we would delete shared_prefs here.

# 4. Launch Avare
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# 5. Handle any startup dialogs (like "Turn on GPS")
# Press Back just in case
input keyevent KEYCODE_BACK
sleep 1

# 6. Ensure we are on the Map screen
# We can send an Intent or just assume launch goes to Map (standard Avare behavior)

# 7. Take initial screenshot for reference
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="