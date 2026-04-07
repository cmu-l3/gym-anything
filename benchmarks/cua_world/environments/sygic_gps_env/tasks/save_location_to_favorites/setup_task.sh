#!/system/bin/sh
set -e
echo "=== Setting up save_location_to_favorites task ==="

# Record task start time
date +%s > /sdcard/task_start_time.txt

PACKAGE="com.sygic.aura"

# Force stop to ensure clean state (closes any open menus/dialogs)
echo "Force stopping Sygic..."
am force-stop $PACKAGE
sleep 2

# Launch Sygic GPS
echo "Launching Sygic GPS..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# Wait for app to load (allow time for map rendering)
sleep 15

# Ensure we are on the main map (press back just in case we are deep in a menu from restored state)
# Sygic usually resets to map on fresh launch after force stop, but good to be safe
# However, too many backs exits the app. 
# We'll assume force-stop resets UI stack to main activity default.

# Dismiss "Your map is ready" sheet if it appears (common on start)
# Coordinates approx [860, 1510] based on env setup script
input tap 860 1510 2>/dev/null || true
sleep 2

# Take screenshot of initial state
screencap -p /sdcard/task_initial_state.png

echo "=== Task setup complete - Sygic on main map view ==="