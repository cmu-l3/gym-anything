#!/system/bin/sh
# Setup script for Sunitinib Antihypertensive Evaluation task

echo "=== Setting up task ==="

# 1. Clean up previous artifacts
rm -f /sdcard/sunitinib_bp_report.txt 2>/dev/null
rm -f /sdcard/task_result.json 2>/dev/null
rm -f /sdcard/final_screenshot.png 2>/dev/null

# 2. Record start time for anti-gaming verification
# Android date +%s usually works
date +%s > /sdcard/task_start_time.txt

# 3. Ensure app is in a clean state (start from fresh)
PACKAGE="com.liverpooluni.ichartoncology"
am force-stop $PACKAGE
sleep 1

# 4. Launch the app
echo "Launching Cancer iChart..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 5. Handle any potential crash/restore dialogs if they appear (simple tap in center)
# Not always needed, but good for robustness
# input tap 540 1200 2>/dev/null

echo "=== Task setup complete ==="