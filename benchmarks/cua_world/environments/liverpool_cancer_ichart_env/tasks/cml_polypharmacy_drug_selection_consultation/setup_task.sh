#!/system/bin/sh
echo "=== Setting up CML Polypharmacy Drug Selection Consultation Task ==="

PACKAGE="com.liverpooluni.ichartoncology"
OUTPUT_FILE="/sdcard/Download/cml_drug_safety_report.txt"

# 1. Clean up any previous results BEFORE recording timestamp
rm -f "$OUTPUT_FILE"
rm -f /sdcard/task_result.json
rm -f /sdcard/final_screenshot.png

# 2. Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt
echo "Task start time recorded: $(cat /sdcard/task_start_time.txt)"

# 3. Ensure Download directory exists
mkdir -p /sdcard/Download

# 4. Ensure the app is closed to start from a clean state
am force-stop $PACKAGE
sleep 2

# 5. Return to home screen
input keyevent KEYCODE_HOME
sleep 1
input keyevent KEYCODE_HOME
sleep 2

# 6. Launch the app using robust helper
echo "Launching Cancer iChart..."
. /sdcard/scripts/launch_helper.sh
launch_cancer_ichart

echo "=== Setup complete ==="
