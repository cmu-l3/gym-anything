#!/system/bin/sh
echo "=== Setting up download_map_hawaii task ==="

PACKAGE="com.sygic.aura"
MAP_DIR="/sdcard/Android/data/com.sygic.aura/files/Maps"

# 1. Record start time
date +%s > /sdcard/task_start_time.txt

# 2. Force stop app to ensure clean state
am force-stop $PACKAGE
sleep 2

# 3. Remove Hawaii map if it exists (RESET STATE)
# Sygic maps usually follow naming like 'us_hawaii.2dc' or similar inside folder structures
# We search and destroy to ensure the agent has to download it.
echo "Cleaning up existing Hawaii maps..."
find "$MAP_DIR" -name "*hawaii*" -exec rm -rf {} + 2>/dev/null
find "$MAP_DIR" -name "*us_hi*" -exec rm -rf {} + 2>/dev/null

# 4. Launch Application
echo "Launching Sygic..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1
sleep 15

# 5. Ensure we are not stuck on a splash screen (basic interaction)
# Tap center of screen just in case a "What's new" dialog is up
input tap 540 1200
sleep 2

# 6. Capture initial state
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="