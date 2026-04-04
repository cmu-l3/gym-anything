#!/system/bin/sh
# Setup script for audit_travel_meds_cabozantinib
# Runs on Android device

echo "=== Setting up Travel Meds Audit Task ==="

PACKAGE="com.liverpooluni.ichartoncology"
REPORT_FILE="/sdcard/travel_safety_report.txt"

# 1. Clean up previous artifacts
rm -f "$REPORT_FILE" 2>/dev/null
rm -f /sdcard/task_result.json 2>/dev/null
rm -f /sdcard/final_screenshot.png 2>/dev/null

# 2. Record task start time (Android specific date format handling)
# Android's date +%s usually works
date +%s > /sdcard/task_start_time.txt

# 3. Ensure app is closed to start fresh
echo "Force stopping app..."
am force-stop "$PACKAGE"
sleep 2

# 4. Launch app to home screen
echo "Launching Cancer iChart..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 5. Ensure we are at the main screen (handle potential 'Resume' or welcome screens)
# Sending Back key a few times can help clear stack if needed, but force-stop usually resets.
# We'll assume force-stop + launch lands on Home/Welcome.

echo "=== Setup Complete ==="