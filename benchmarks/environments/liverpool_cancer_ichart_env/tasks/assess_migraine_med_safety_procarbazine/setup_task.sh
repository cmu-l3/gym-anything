#!/system/bin/sh
echo "=== Setting up Migraine Safety Task ==="

# Define package and file paths
PACKAGE="com.liverpooluni.ichartoncology"
REPORT_FILE="/sdcard/migraine_safety_report.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"

# 1. Clean up previous artifacts
rm -f "$REPORT_FILE"
rm -f "$START_TIME_FILE"
rm -f "/sdcard/task_result.json"

# 2. Record start time (using date +%s if available, else standard date)
date +%s > "$START_TIME_FILE" 2>/dev/null || date > "$START_TIME_FILE"

# 3. Ensure clean app state
echo "Force stopping app..."
am force-stop "$PACKAGE"
sleep 2

# 4. Return to Home Screen
echo "Going to home screen..."
input keyevent KEYCODE_HOME
sleep 1

# 5. Launch App (Warmup)
# We launch it to ensure it's ready, then go back to home so the agent starts 'fresh' but with app cached
echo "Warming up app..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 6. Return to Home Screen for agent start
input keyevent KEYCODE_HOME
sleep 1

# 7. Take initial screenshot evidence
screencap -p /sdcard/initial_state.png

echo "=== Setup Complete ==="