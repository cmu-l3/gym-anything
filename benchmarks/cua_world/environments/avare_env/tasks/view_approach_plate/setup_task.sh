#!/system/bin/sh
# setup_task.sh for view_approach_plate@1
# Runs on Android device

set -e
echo "=== Setting up view_approach_plate task ==="

# 1. Record task start time for anti-gaming (epoch seconds)
date +%s > /sdcard/task_start_time.txt

PACKAGE="com.ds.avare"

# 2. Force stop to get clean state
am force-stop $PACKAGE
sleep 2

# 3. Clean up existing plate data to ensure agent performs download
# Avare typically stores data in specific directories. We want to remove 'plates' specific files
# but keep the charts/maps/databases so the app is usable.
echo "Cleaning old plate data..."

# Path 1: External storage (typical for maps/plates)
AVARE_EXT="/sdcard/Android/data/com.ds.avare/files"
if [ -d "$AVARE_EXT" ]; then
    # Delete anything looking like a plate database or directory
    find "$AVARE_EXT" -name "*plate*" -o -name "*Plate*" | xargs rm -rf 2>/dev/null || true
    # Also look for specific structure if known (e.g., plates/ subdirectory)
    rm -rf "$AVARE_EXT/plates" 2>/dev/null || true
fi

# Path 2: Internal storage (less common for big data but check anyway)
AVARE_INT="/data/data/com.ds.avare/files"
if [ -d "$AVARE_INT" ]; then
    find "$AVARE_INT" -name "*plate*" -o -name "*Plate*" | xargs rm -rf 2>/dev/null || true
fi

sleep 1

# 4. Launch Avare to main map view
echo "Launching Avare..."
. /sdcard/scripts/launch_helper.sh
launch_avare

# 6. Take initial state screenshot
screencap -p /sdcard/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Avare is on main map view. Plate data has been cleared."