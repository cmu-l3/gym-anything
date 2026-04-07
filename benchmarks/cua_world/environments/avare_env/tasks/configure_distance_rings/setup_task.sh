#!/system/bin/sh
# Setup script for configure_distance_rings
# Runs on Android environment

echo "=== Setting up Configure Distance Rings Task ==="

# Create task directory
mkdir -p /sdcard/tasks/configure_distance_rings

# 1. Record Start Time
date +%s > /sdcard/tasks/configure_distance_rings/start_time.txt

# 2. Reset/Clean State (Optional but good practice)
# We don't want to wipe all data (maps), but we might want to ensure app is running fresh.
# For this task, we'll just force stop to ensure a clean launch.
am force-stop com.ds.avare

# 3. Launch Avare
echo "Launching Avare..."
monkey -p com.ds.avare -c android.intent.category.LAUNCHER 1

# 4. Wait for App to Load
sleep 10

# 5. Dismiss any potential dialogs (Terms, etc. if first run, though env setup should handle this)
# Press Back just in case a menu is open
input keyevent 4
sleep 1

# 6. Capture Initial State Screenshot
screencap -p /sdcard/tasks/configure_distance_rings/initial_state.png

echo "=== Setup Complete ==="