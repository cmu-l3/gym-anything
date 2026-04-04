#!/system/bin/sh
echo "=== Setting up select_safer_insomnia_medication_crizotinib ==="

# Define paths
TASK_DIR="/sdcard/tasks/select_safer_insomnia_medication_crizotinib"
OUTPUT_FILE="/sdcard/insomnia_safety_report.txt"
PACKAGE="com.liverpooluni.ichartoncology"

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# Clean up previous artifacts
rm -f "$OUTPUT_FILE"
rm -f /sdcard/task_result.json

# Force stop the app to ensure a clean start
am force-stop "$PACKAGE"
sleep 1

# Ensure we are at Home screen
input keyevent KEYCODE_HOME
sleep 2

# Launch the application
echo "Launching Cancer iChart..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# Verify app launch
if dumpsys window | grep -q "$PACKAGE"; then
    echo "App launched successfully."
else
    echo "WARNING: App launch might have failed."
fi

# Take initial screenshot for evidence
screencap -p /sdcard/task_initial.png
echo "Initial state captured."

echo "=== Task setup complete ==="