#!/system/bin/sh
echo "=== Setting up download_offline_map_monaco task ==="

# 1. Record Start Time
date +%s > /sdcard/task_start_time.txt

# 2. Record Initial Map State
# We look in the standard Android data path for Sygic maps
MAPS_DIR="/sdcard/Android/data/com.sygic.aura/files/Maps"
mkdir -p "$MAPS_DIR"

echo "Recording initial map files..."
ls -R "$MAPS_DIR" > /sdcard/initial_maps_list.txt 2>/dev/null

# Calculate initial size of maps folder
du -s "$MAPS_DIR" > /sdcard/initial_maps_size.txt 2>/dev/null

# 3. Ensure Sygic is Running
PACKAGE="com.sygic.aura"
echo "Launching Sygic GPS Navigation..."

# Force stop to ensure clean UI state (back to map)
am force-stop $PACKAGE
sleep 2

# Launch App
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 15

# 4. Handle any "Resume" or "Welcome" dialogs if they appear (simple tap attempt)
# Tapping center of screen to dismiss potential popups
input tap 540 1200
sleep 2

# 5. Capture Initial Screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="