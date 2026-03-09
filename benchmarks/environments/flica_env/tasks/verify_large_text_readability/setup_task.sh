#!/system/bin/sh
# Setup script for verify_large_text_readability
# Ensures app is logged in and Font Scale is reset to default

echo "=== Setting up Large Text Verification Task ==="

# 1. Reset Font Scale to default (1.0) to ensure the agent actually does work
# This prevents "do nothing" gaming if the env was already dirty
echo "Resetting system font scale to 1.0..."
settings put system font_scale 1.0

# 2. Record start time for anti-gaming timestamps
date +%s > /sdcard/task_start_time.txt

# 3. Clean up previous evidence if it exists
rm -f /sdcard/large_text_test.png
rm -f /sdcard/readability_result.txt
rm -f /sdcard/task_result.json

# 4. Use Login Helper to ensure we are on the Friends page
# This script handles force-stop and relaunch, ensuring a clean app state
echo "Ensuring app is logged in..."
sh /sdcard/scripts/login_helper.sh

# 5. Capture initial state
echo "Capturing initial state..."
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="
echo "System font scale: $(settings get system font_scale)"
echo "App should be on Friends page."