#!/system/bin/sh
set -e
echo "=== Setting up record_app_info task ==="

# 1. Clean up previous artifacts
rm -f /sdcard/app_info_report.txt
rm -rf /data/local/tmp/ground_truth
mkdir -p /data/local/tmp/ground_truth

# 2. Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# 3. Extract Ground Truth Data
PACKAGE="com.robert.fcView"

# Get version from package manager
# dumpsys output format: "    versionName=2.4.5"
VERSION_NAME=$(dumpsys package $PACKAGE | grep "versionName" | head -1 | sed 's/.*versionName=//' | tr -d '[:space:]')
VERSION_CODE=$(dumpsys package $PACKAGE | grep "versionCode" | head -1 | sed 's/.*versionCode=//' | sed 's/ .*//' | tr -d '[:space:]')

echo "Ground truth version: $VERSION_NAME (code: $VERSION_CODE)"

# Save ground truth to hidden location (not readable by agent ideally, but acceptable in this env)
echo "$VERSION_NAME" > /data/local/tmp/ground_truth/version.txt
echo "$VERSION_CODE" > /data/local/tmp/ground_truth/version_code.txt

# The developer email is static for this app but we store it for the verifier
# Common email found in Play Store and About page
echo "robert@flightcrewview.com" > /data/local/tmp/ground_truth/developer_email.txt

chmod -R 777 /data/local/tmp/ground_truth

# 4. Ensure App is in Correct State (Logged in, Home Screen)
echo "Ensuring app is logged in..."
sh /sdcard/scripts/login_helper.sh

# 5. Capture Initial State Screenshot
screencap -p /sdcard/task_initial_state.png

echo "=== Task setup complete ==="
echo "Agent starts at Friends page."