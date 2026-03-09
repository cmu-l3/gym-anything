#!/system/bin/sh
echo "=== Setting up check_domperidone_across_cancer_drugs ==="

# Define package
PACKAGE="com.liverpooluni.ichartoncology"

# 1. Clean up previous artifacts
rm -f /sdcard/domperidone_report.txt
rm -f /sdcard/task_result.json
rm -f /sdcard/task_start_time.txt

# 2. Record start time (using date +%s if available, else standard format)
date +%s > /sdcard/task_start_time.txt 2>/dev/null || date > /sdcard/task_start_time.txt

# 3. Force stop the app to ensure clean start
echo "Force stopping app..."
am force-stop $PACKAGE
sleep 1

# 4. Go to Home Screen
echo "Navigating to Home..."
input keyevent KEYCODE_HOME
sleep 1

# 5. Take initial screenshot (for debugging/evidence)
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="