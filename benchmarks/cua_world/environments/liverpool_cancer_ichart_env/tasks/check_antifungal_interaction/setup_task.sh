#!/system/bin/sh
# Setup for check_antifungal_interaction task
echo "=== Setting up check_antifungal_interaction task ==="

# Define package name
PACKAGE="com.liverpooluni.ichartoncology"

# Record task start time for anti-gaming verification
date +%s > /sdcard/tasks/task_start_time.txt

# 1. Force stop the app to ensure a clean starting state
# We do NOT clear app data because we want to keep the downloaded interaction database
echo "Stopping Cancer iChart app..."
am force-stop $PACKAGE 2>/dev/null
sleep 2

# 2. Go to Home screen
echo "Navigating to Home screen..."
input keyevent KEYCODE_HOME
sleep 2

# 3. Verify installation
if ! pm list packages | grep -q "$PACKAGE"; then
    echo "ERROR: Cancer iChart is not installed!"
    # In a real scenario, we might try to install, but here we assume env is correct
    exit 1
fi

# 4. Check if interaction database is likely present (simple size check)
# App data usually grows beyond 100KB when DB is downloaded
APP_DATA_SIZE=$(du -s /data/data/$PACKAGE 2>/dev/null | awk '{print $1}')
echo "App data size: $APP_DATA_SIZE blocks"

# If size is too small, the DB might not be downloaded. 
# The environment setup usually handles this, but we can try a quick repair if needed.
if [ "$APP_DATA_SIZE" -lt 50 ]; then
    echo "WARNING: App data seems small. Interaction DB might be missing."
    # We won't block here, but we'll log it. 
    # The agent might have to handle the download dialog if it appears.
fi

# 5. Launch the app using robust helper
echo "Launching Cancer iChart..."
. /sdcard/scripts/launch_helper.sh
launch_cancer_ichart

# 6. Capture initial state screenshot
screencap -p /sdcard/tasks/initial_state.png 2>/dev/null

echo "=== Task setup complete ==="