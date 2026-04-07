#!/system/bin/sh
# Setup script for delete_offline_map task
# Runs on Android device

echo "=== Setting up delete_offline_map task ==="

PACKAGE="com.sygic.aura"
TASK_DIR="/sdcard/tasks/delete_offline_map"
mkdir -p "$TASK_DIR"

# 1. Record Task Start Time
date +%s > "/sdcard/task_start_time.txt"

# 2. Ensure Sygic is closed to start fresh
am force-stop "$PACKAGE"
sleep 2

# 3. Check if 'American Samoa' map files exist (Baseline)
# Sygic maps are usually in /sdcard/Android/data/... or /data/data/...
# We check common locations.
echo "Checking for existing map files..."
MAP_FILES=$(find /sdcard/Android/data/$PACKAGE/ /data/data/$PACKAGE/ -type f -name "*samoa*" -o -name "*as.map*" 2>/dev/null)

if [ -z "$MAP_FILES" ]; then
    echo "WARNING: American Samoa map not found on disk. Attempting to download or fail."
    # In a real scenario, we might try to trigger download here or fail.
    # For this task, we assume the environment 'setup_sygic_gps.sh' (warmup) handled it.
    # We will record "0" to indicate missing start state, which might invalidate the task
    # but we proceed hoping it's just a naming mismatch.
    echo "0" > "/sdcard/initial_map_count.txt"
else
    echo "Map files found."
    echo "$MAP_FILES" | wc -l > "/sdcard/initial_map_count.txt"
    # Save list for debugging
    echo "$MAP_FILES" > "/sdcard/initial_map_list.txt"
fi

# 4. Record Initial Storage Size
du -s /data/data/$PACKAGE/ 2>/dev/null | awk '{print $1}' > "/sdcard/initial_storage_size.txt"

# 5. Launch App to Main Screen
echo "Launching Sygic GPS..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 15

# 6. Ensure we are on the map screen (simple heuristic: press back to clear overlays)
# Dismiss potential "Upgrade to Premium" or "Map Ready" sheets
input keyevent KEYCODE_BACK
sleep 2
input tap 860 1510  # Tap potential 'Close' on bottom sheet
sleep 1

# 7. Take Initial Screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="