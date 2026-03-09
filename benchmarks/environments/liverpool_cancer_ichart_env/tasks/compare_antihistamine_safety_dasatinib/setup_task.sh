#!/system/bin/sh
# Setup script for Compare Antihistamine Safety task

echo "=== Setting up compare_antihistamine_safety_dasatinib ==="

# Record start time for anti-gaming (using date +%s if available, else just a marker)
date +%s > /sdcard/task_start_time.txt 2>/dev/null || echo "0" > /sdcard/task_start_time.txt

# Remove any previous report to ensure clean state
rm -f /sdcard/dasatinib_antihistamine_report.txt
rm -f /sdcard/task_result.json

PACKAGE="com.liverpooluni.ichartoncology"

# Ensure clean app state
echo "Force stopping app..."
am force-stop $PACKAGE
sleep 1

# Launch the app to the home screen
echo "Launching Cancer iChart..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# Ensure we are not stuck on a previous screen (press Back a few times just in case, though force-stop usually clears it)
# input keyevent KEYCODE_BACK
# sleep 1

echo "=== Setup Complete ==="