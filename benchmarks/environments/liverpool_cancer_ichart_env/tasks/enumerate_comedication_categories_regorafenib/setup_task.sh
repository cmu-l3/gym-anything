#!/system/bin/sh
echo "=== Setting up Regorafenib Enumeration Task ==="

PACKAGE="com.liverpooluni.ichartoncology"
REPORT_PATH="/sdcard/regorafenib_categories_report.txt"

# 1. Clean up previous artifacts
rm -f "$REPORT_PATH"
rm -f "/sdcard/task_result.json"

# 2. Record start time for anti-gaming (using Unix timestamp)
date +%s > /sdcard/task_start_time.txt

# 3. Ensure app is closed to start fresh
am force-stop "$PACKAGE"
sleep 2

# 4. Launch App to initial state (Home/Welcome screen)
echo "Launching Cancer iChart..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1
sleep 5

# 5. Take initial screenshot for evidence
screencap -p /sdcard/initial_state.png

echo "=== Setup Complete ==="