#!/system/bin/sh
# Setup script for verify_landscape_layout task
# Runs on Android device

echo "=== Setting up Verify Landscape Layout task ==="

# Record task start time
date +%s > /sdcard/task_start_time.txt

# Clean up previous artifacts
rm -f /sdcard/landscape_proof.png
rm -f /sdcard/rotation_report.txt
rm -f /sdcard/task_result.json

# Ensure device starts in Portrait mode (Rotation 0)
echo "Resetting rotation to Portrait..."
settings put system accelerometer_rotation 0
settings put system user_rotation 0
sleep 2

# Ensure Flight Crew View is running and logged in
# Using the environment's login helper script
if [ -f /sdcard/scripts/login_helper.sh ]; then
    sh /sdcard/scripts/login_helper.sh
else
    echo "WARNING: login_helper.sh not found, launching app manually"
    monkey -p com.robert.fcView -c android.intent.category.LAUNCHER 1
    sleep 5
fi

# Verify app is foreground
echo "Verifying app focus..."
dumpsys window displays | grep -E 'mCurrentFocus'

echo "=== Setup Complete ==="
echo "Device is in Portrait mode. App is running."