#!/system/bin/sh
echo "=== Setting up Compare Macrolides Task ==="

PACKAGE="com.liverpooluni.ichartoncology"
OUTPUT_FILE="/sdcard/lorlatinib_macrolide_report.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"

# 1. Clean up previous artifacts
rm -f "$OUTPUT_FILE"
rm -f "/sdcard/task_result.json"

# 2. Record start time (standard Unix timestamp)
date +%s > "$START_TIME_FILE"
echo "Task start time recorded: $(cat $START_TIME_FILE)"

# 3. Ensure app is in a clean state (force stop)
echo "Force stopping app..."
am force-stop "$PACKAGE"
sleep 2

# 4. Launch app to Welcome screen
echo "Launching Cancer iChart..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 5. Handle any potential crash/dialogs by waiting
# (The env setup script handles the initial DB download, so we assume it's ready)

# 6. Take initial screenshot for evidence
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="