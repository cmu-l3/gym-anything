#!/system/bin/sh
# Setup script for set_map_font_size_large
# Runs on Android device

echo "=== Setting up set_map_font_size_large task ==="

# 1. Record Start Time
date +%s > /sdcard/task_start_time.txt

# 2. Reset/Ensure App State
PACKAGE="com.sygic.aura"

# Force stop to ensure clean start
am force-stop $PACKAGE
sleep 2

# Press Home to clear any overlays
input keyevent KEYCODE_HOME
sleep 1

# Launch Sygic
echo "Launching Sygic GPS Navigation..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# Ensure we are on the main screen (not stuck in a menu from previous run)
# We can try to press Back a few times just in case, but force-stop usually resets stack
# However, Sygic might remember last screen.
# Let's assume force-stop resets to main map or splash.

echo "=== Setup complete ==="