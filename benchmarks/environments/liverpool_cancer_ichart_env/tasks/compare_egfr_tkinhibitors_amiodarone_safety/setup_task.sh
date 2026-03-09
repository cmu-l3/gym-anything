#!/system/bin/sh
# Setup script for EGFR inhibitor comparison task
# Runs on Android device

echo "=== Setting up EGFR Comparison Task ==="

# 1. Record Task Start Time (using date +%s if available, or system property)
# Android shell sometimes has limited date. We'll try to write to a file.
date +%s > /sdcard/task_start_time.txt
echo "Task start time recorded: $(cat /sdcard/task_start_time.txt)"

# 2. Cleanup previous runs
rm -f /sdcard/egfr_amiodarone_comparison.md
rm -f /sdcard/task_result.json

# 3. Ensure App is in Clean State
PACKAGE="com.liverpooluni.ichartoncology"
echo "Force stopping $PACKAGE..."
am force-stop $PACKAGE
sleep 2

# 4. Launch App
echo "Launching Cancer iChart..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 5. Dismiss "Interaction Data" dialog if it appears (tap OK)
# Coordinates approx [815, 1403] for OK button on 1080x2400
# We blindly tap just in case, though the env setup should have handled it.
input tap 815 1403
sleep 1

# 6. Ensure we are at Home/Welcome screen
# If the app was already open, we might be deep in menus. Force stop ensured clean start.
# The app usually starts at the disclaimer or home.
echo "Setup complete. App launched."