#!/system/bin/sh
# Setup script for lookup_past_flight_status task

echo "=== Setting up lookup_past_flight_status task ==="

# 1. Record task start time for anti-gaming (epoch seconds)
date +%s > /sdcard/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /sdcard/past_flight_result.png
rm -f /sdcard/task_result.json
rm -f /sdcard/ui_dump.xml

# 3. Ensure App is running and logged in
# Use the shared login helper to ensure we start at the Friends (Home) page
if [ -f "/sdcard/scripts/login_helper.sh" ]; then
    sh /sdcard/scripts/login_helper.sh
else
    echo "WARNING: login_helper.sh not found, attempting raw launch"
    monkey -p com.robert.fcView -c android.intent.category.LAUNCHER 1
    sleep 5
fi

# 4. Record the specific "Yesterday" date for verification later
# We calculate this on the device to ensure timezone matches
# Android shell date math can be tricky, relying on python verifier to calculate 'yesterday' 
# based on the device's current date is safer, but let's store current date.
date +%Y-%m-%d > /sdcard/task_initial_date.txt

echo "=== Task setup complete ==="
echo "Device date: $(date)"