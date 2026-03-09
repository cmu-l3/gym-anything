#!/system/bin/sh
echo "=== Setting up Ribociclib Risk Analysis Task ==="

PACKAGE="com.liverpooluni.ichartoncology"
OUTPUT_FILE="/sdcard/ribociclib_risk_analysis.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"

# 1. Clean up previous artifacts
rm -f "$OUTPUT_FILE"
rm -f "/sdcard/task_result.json"

# 2. Record start time (Android date +%s usually works)
date +%s > "$START_TIME_FILE"

# 3. Ensure clean app state
echo "Force stopping app..."
am force-stop "$PACKAGE"
sleep 1

# 4. Launch app to home screen
echo "Launching app..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1
sleep 5

# 5. Ensure we aren't stuck in a dialog (simple tap to clear welcome if needed, though usually not needed after force stop if data cleared, but here we persist data so just launch)
# (Optional: Input keyevents to clear splash if known issue, but standard launch is usually fine)

echo "=== Setup Complete ==="