#!/system/bin/sh
# Setup script for assess_diarrhea_management_safety_lapatinib
# Runs inside the Android environment

echo "=== Setting up Lapatinib Diarrhea Management Task ==="

PACKAGE="com.liverpooluni.ichartoncology"
TASK_DIR="/sdcard/tasks/assess_diarrhea_management_safety_lapatinib"
OUTPUT_FILE="/sdcard/Download/lapatinib_supportive_care_report.txt"

# 1. Clean up previous artifacts
rm -f "$OUTPUT_FILE"
rm -f "/sdcard/task_result.json"
rm -f "/sdcard/final_screenshot.png"

# 2. Record start time (using date +%s if available, else generic marker)
date +%s > /sdcard/task_start_time.txt 2>/dev/null || echo "0" > /sdcard/task_start_time.txt

# 3. Ensure clean app state
echo "Force stopping app..."
am force-stop $PACKAGE
sleep 2

# 4. Return to Home Screen
input keyevent KEYCODE_HOME
sleep 1

# 5. Launch App
echo "Launching Cancer iChart..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 6. Verify launch (simple check if window is focused, retry if needed)
# Note: grep pattern depends on specific activity name, usually package name appears in mCurrentFocus
FOCUS=$(dumpsys window | grep mCurrentFocus)
if ! echo "$FOCUS" | grep -q "$PACKAGE"; then
    echo "App didn't launch, retrying..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

echo "=== Task Setup Complete ==="