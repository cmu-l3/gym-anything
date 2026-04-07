#!/system/bin/sh
# Setup script for remove_plan_waypoint task.
# Launches Avare and creates the initial flight plan: KOAK KSCK KMOD KFAT

echo "=== Setting up remove_plan_waypoint task ==="

PACKAGE="com.ds.avare"
ACTIVITY="com.ds.avare.MainActivity"

# 1. Force stop to ensure clean state
am force-stop $PACKAGE
sleep 2

# 2. Launch Avare
echo "Launching Avare..."
. /sdcard/scripts/launch_helper.sh
launch_avare

# 3. Create the flight plan via UI automation
# We assume the 'Plan' tab accepts a space-separated string or we add them sequentially.
# For robustness on different screen sizes, we attempt a common workflow:
# Tap 'Plan' tab -> Type route string -> Enter

# Coordinates for 1080x2400 resolution (Pixel 5/6 Emulator)
# Bottom bar tabs approx Y=2300.
# Tabs: Map, Plates, Plan, Near, Find, Menu
# Plan tab approx X=450-500? Let's try X=450 Y=2350
PLAN_TAB_X=450
PLAN_TAB_Y=2350

echo "Navigating to Plan tab..."
input tap $PLAN_TAB_X $PLAN_TAB_Y
sleep 2

# Tap 'New' or 'Clear' to ensure empty list.
# Usually in top menu. Let's assume the agent handles minor cleanups, but we try to clear.
# Tap 'Menu' (bottom right) -> 'New' (if available in Plan view).
# For now, we'll just try to add the route.

# Tap the search/add text field at the top
# Approx X=540 Y=200
echo "Focusing plan input field..."
input tap 540 200
sleep 1

# Clear existing text (move cursor to end, then delete chars)
# 123 move to end keycode, 67 backspace
input keyevent 123
for i in $(seq 1 20); do input keyevent 67; done

# Type the full route
echo "Entering flight plan..."
input text "KOAK KSCK KMOD KFAT"
sleep 1

# Press Enter/Search to process the route
input keyevent 66
sleep 5

# Return to Map view to start the task
# Map tab is usually the first one on the left
MAP_TAB_X=100
MAP_TAB_Y=2350

echo "Returning to Map view..."
input tap $MAP_TAB_X $MAP_TAB_Y
sleep 3

# 4. Record task start time for anti-gaming
date +%s > /sdcard/task_start_time.txt

# 5. Capture initial state
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="
echo "Flight plan KOAK->KSCK->KMOD->KFAT created."