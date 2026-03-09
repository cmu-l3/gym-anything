#!/system/bin/sh
# Setup script for check_running_memory
# Runs on Android environment

echo "=== Setting up Memory Check Task ==="

# 1. Disable Developer Options initially to ensure the agent has to enable them
echo "Disabling Developer Options..."
settings put global development_settings_enabled 0

# 2. Ensure Flight Crew View is running (so it appears in Running Services)
# We use the helper script which handles login/launch
if [ -f "/sdcard/scripts/login_helper.sh" ]; then
    sh /sdcard/scripts/login_helper.sh
else
    # Fallback if helper missing
    monkey -p com.robert.fcView -c android.intent.category.LAUNCHER 1
    sleep 5
fi

# 3. Go back to Home screen so agent starts from neutral state
input keyevent KEYCODE_HOME
sleep 1

# 4. Clean up previous artifacts
rm -f /sdcard/ram_audit.txt
rm -f /sdcard/ram_evidence.png
rm -f /sdcard/task_result.json

# 5. Record start time (using system uptime as proxy if date is wonky, but date +%s usually works on Android)
date +%s > /sdcard/task_start_time.txt

echo "=== Setup Complete ==="