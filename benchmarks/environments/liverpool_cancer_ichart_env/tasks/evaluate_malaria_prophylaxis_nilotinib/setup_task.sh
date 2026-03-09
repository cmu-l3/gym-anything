#!/system/bin/sh
# Setup script for evaluate_malaria_prophylaxis_nilotinib task

echo "=== Setting up Malaria Prophylaxis Evaluation Task ==="

PACKAGE="com.liverpooluni.ichartoncology"
REPORT_PATH="/sdcard/nilotinib_malaria_report.txt"

# 1. Clean up previous artifacts
rm -f "$REPORT_PATH" 2>/dev/null
rm -f /sdcard/task_result.json 2>/dev/null
rm -f /sdcard/task_start_time.txt 2>/dev/null

# 2. Record start time (using date +%s if available, else just date)
date +%s > /sdcard/task_start_time.txt 2>/dev/null || date > /sdcard/task_start_time.txt

# 3. Ensure app is in a clean state (Force stop and launch)
echo "Restarting Cancer iChart app..."
am force-stop $PACKAGE
sleep 2

# Launch to main activity
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 4. Verify app launch
CURRENT_FOCUS=$(dumpsys window | grep mCurrentFocus)
echo "Current focus: $CURRENT_FOCUS"

echo "=== Setup Complete ==="