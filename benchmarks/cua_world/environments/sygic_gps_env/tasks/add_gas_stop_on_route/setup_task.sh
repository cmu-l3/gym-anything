#!/system/bin/sh
# Setup script for add_gas_stop_on_route
# Runs on Android device

echo "=== Setting up add_gas_stop_on_route task ==="

# Record start time
date +%s > /sdcard/task_start_time.txt

PACKAGE="com.sygic.aura"

# Force stop to ensure clean state
echo "Force stopping Sygic..."
am force-stop $PACKAGE
sleep 2

# Press Home to reset UI stack
input keyevent KEYCODE_HOME
sleep 1

# Launch Sygic
echo "Launching Sygic GPS Navigation..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# Wait for app to load (simple sleep strategy for Android shell)
sleep 15

# Ensure we are not stuck on a splash screen or dialog
# Tap center just in case of a "Welcome" or "Update" sheet
input tap 540 1200 2>/dev/null || true
sleep 1

echo "=== Setup complete ==="