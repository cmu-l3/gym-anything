#!/system/bin/sh
echo "=== Setting up check_anti_tb_interaction_with_sunitinib task ==="

# 1. Record task start time (using standard Unix timestamp)
date +%s > /sdcard/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /sdcard/Download/interaction_result.txt
rm -f /sdcard/task_result.json

# 3. Ensure the app is closed and in a clean state
PACKAGE="com.liverpooluni.ichartoncology"
am force-stop "$PACKAGE"

# 4. Navigate to Home Screen to ensure neutral starting state
input keyevent KEYCODE_HOME
sleep 1
input keyevent KEYCODE_HOME
sleep 1

# 5. Verify App is installed (sanity check)
if pm list packages | grep -q "$PACKAGE"; then
    echo "App is installed."
else
    echo "ERROR: App $PACKAGE not found!"
fi

# 6. Ensure Download directory exists
mkdir -p /sdcard/Download

# 7. Launch the app using robust helper
echo "Launching Cancer iChart..."
. /sdcard/scripts/launch_helper.sh
launch_cancer_ichart

echo "=== Task setup complete ==="