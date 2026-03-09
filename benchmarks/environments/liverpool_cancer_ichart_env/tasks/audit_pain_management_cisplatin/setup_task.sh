#!/system/bin/sh
echo "=== Setting up audit_pain_management_cisplatin task ==="

PACKAGE="com.liverpooluni.ichartoncology"
OUTPUT_FILE="/sdcard/cisplatin_pain_audit.txt"
RESULT_JSON="/sdcard/task_result.json"

# 1. Clean up previous artifacts
rm -f "$OUTPUT_FILE"
rm -f "$RESULT_JSON"
rm -f /sdcard/final_screenshot.png

# 2. Record start time for anti-gaming (using Unix timestamp)
date +%s > /sdcard/task_start_time.txt

# 3. Ensure app is closed to start fresh
am force-stop "$PACKAGE"
sleep 2

# 4. Launch app to ensure it's ready
echo "Launching Cancer iChart..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1
sleep 5

# 5. Go to Home if needed (simple heuristic)
input keyevent KEYCODE_HOME
sleep 1
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1
sleep 2

echo "=== Setup complete ==="