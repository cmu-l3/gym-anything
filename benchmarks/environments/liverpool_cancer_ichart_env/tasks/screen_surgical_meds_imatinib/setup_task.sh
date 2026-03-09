#!/system/bin/sh
# Setup script for screen_surgical_meds_imatinib
# Runs on Android device via ADB shell

echo "=== Setting up Surgical Meds Screen Task ==="

PACKAGE="com.liverpooluni.ichartoncology"
REPORT_FILE="/sdcard/surgical_screen_imatinib.txt"

# 1. Clean up previous artifacts
rm -f "$REPORT_FILE" 2>/dev/null
rm -f "/sdcard/task_result.json" 2>/dev/null
rm -f "/sdcard/task_start_time.txt" 2>/dev/null

# 2. Record start time (using date +%s if available, else simple timestamp)
date +%s > /sdcard/task_start_time.txt 2>/dev/null || date > /sdcard/task_start_time.txt

# 3. Force stop the app to ensure clean state
echo "Stopping Cancer iChart..."
am force-stop "$PACKAGE"
sleep 2

# 4. Return to Home Screen
echo "Going to Home Screen..."
input keyevent KEYCODE_HOME
sleep 2

# 5. Clear any dialogs (just in case)
input keyevent KEYCODE_ESCAPE 2>/dev/null

echo "=== Setup Complete ==="