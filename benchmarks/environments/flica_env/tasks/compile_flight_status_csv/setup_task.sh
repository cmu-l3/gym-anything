#!/system/bin/sh
echo "=== Setting up compile_flight_status_csv task ==="

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# Clean up any previous attempts
rm -f /sdcard/flight_report.csv
rm -f /sdcard/task_result.json
rm -f /sdcard/final_screenshot.png

# Ensure Flight Crew View is running and logged in
# Using the environment's shared login helper to reach the Friends/Home screen
if [ -f "/sdcard/scripts/login_helper.sh" ]; then
    sh /sdcard/scripts/login_helper.sh
else
    echo "Login helper not found, attempting to launch app directly..."
    monkey -p com.robert.fcView -c android.intent.category.LAUNCHER 1
    sleep 5
fi

# Take initial screenshot for evidence
screencap -p /sdcard/initial_state.png

echo "=== Task setup complete ==="