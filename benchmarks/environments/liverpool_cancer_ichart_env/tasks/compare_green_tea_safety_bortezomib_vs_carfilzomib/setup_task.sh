#!/system/bin/sh
echo "=== Setting up Green Tea Safety Comparison Task ==="

PACKAGE="com.liverpooluni.ichartoncology"
TASK_DIR="/sdcard/tasks/compare_green_tea_safety_bortezomib_vs_carfilzomib"
OUTPUT_FILE="/sdcard/green_tea_safety_report.txt"

# 1. Clean up previous artifacts
rm -f "$OUTPUT_FILE"
rm -f /sdcard/task_result.json
rm -f /sdcard/task_final.png

# 2. Record task start time (for anti-gaming verification)
date +%s > /sdcard/task_start_time.txt

# 3. Ensure app is closed to start from fresh state
am force-stop "$PACKAGE"
sleep 1

# 4. Go to Home Screen
input keyevent KEYCODE_HOME
sleep 1

# 5. Launch Application
echo "Launching Cancer iChart..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1
sleep 5

# 6. Handle any "Rate this app" or "Welcome" dialogs if they appear (heuristic taps)
# Tap center just in case
input tap 540 1200
sleep 1

echo "=== Setup Complete ==="