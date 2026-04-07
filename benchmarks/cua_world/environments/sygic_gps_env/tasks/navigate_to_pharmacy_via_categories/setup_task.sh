#!/system/bin/sh
# Setup script for navigate_to_pharmacy_via_categories
# Runs inside the Android environment

echo "=== Setting up Pharmacy Navigation Task ==="

# 1. Define paths and packages
PACKAGE="com.sygic.aura"
TASK_DIR="/sdcard/tasks/navigate_to_pharmacy_via_categories"
mkdir -p "$TASK_DIR"

# 2. Record start timestamp for anti-gaming
date +%s > "$TASK_DIR/task_start_time.txt"

# 3. Set GPS Location to Kabul, Afghanistan (Area with POIs)
# Lat: 34.535, Lon: 69.172 (Near Kabul University)
echo "Setting GPS location to Kabul..."
cmd location set-location-enabled true
# Note: 'emu geo fix' might not be available inside the shell depending on permissions,
# but usually the environment handles location via the emulator console.
# If running on device/emulator shell, we rely on the environment's geo-fix capability 
# or pre-set state. We will assume the environment sets the location or we rely on 
# the previous state. For robustness, we attempt to force stop to clear any active routes.

# 4. Force stop Sygic to ensure clean state
echo "Force stopping Sygic..."
am force-stop $PACKAGE
sleep 2

# 5. Launch Sygic directly to main activity
echo "Launching Sygic GPS..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# 6. Wait for app to load
echo "Waiting for app to initialize..."
sleep 15

# 7. Dismiss any potential startup dialogs/popups
# Tap "back" just in case a menu or dialog is open
input keyevent KEYCODE_BACK
sleep 1

# 8. Capture initial state screenshot
screencap -p "$TASK_DIR/initial_state.png"

echo "=== Setup Complete ==="