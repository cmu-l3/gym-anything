#!/system/bin/sh
echo "=== Setting up PPI Comparison Task ==="

PACKAGE="com.liverpooluni.ichartoncology"
START_TIME_FILE="/sdcard/task_start_time.txt"

# 1. timestamp for anti-gaming
date +%s > "$START_TIME_FILE"

# 2. Cleanup previous artifacts
rm -f /sdcard/ppi_switch_recommendation.txt 2>/dev/null
rm -f /sdcard/ppi_comparison_table.png 2>/dev/null
rm -f /sdcard/task_result.json 2>/dev/null

# 3. Ensure app is closed for a fresh start
am force-stop "$PACKAGE"
sleep 1

# 4. Go to Home Screen
input keyevent KEYCODE_HOME
sleep 1

# 5. Launch App
echo "Launching Cancer iChart..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null

# 6. Wait for app to load
sleep 5

echo "=== Setup Complete ==="