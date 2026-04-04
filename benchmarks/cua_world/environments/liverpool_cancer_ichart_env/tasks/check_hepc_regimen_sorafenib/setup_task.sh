#!/system/bin/sh
echo "=== Setting up check_hepc_regimen_sorafenib task ==="

PACKAGE="com.liverpooluni.ichartoncology"
OUTPUT_FILE="/sdcard/sorafenib_hepc_report.txt"

# 1. Clean up previous artifacts
rm -f "$OUTPUT_FILE"
rm -f /sdcard/task_result.json
rm -f /sdcard/final_screenshot.png

# 2. Record start time (Android specific method)
# Using date +%s if available, otherwise fallback
date +%s > /sdcard/task_start_time.txt 2>/dev/null || echo "0" > /sdcard/task_start_time.txt

# 3. Force stop app to ensure clean state
am force-stop "$PACKAGE"
sleep 1

# 4. Go to Home screen
input keyevent KEYCODE_HOME
sleep 1

# 5. Launch app
echo "Launching Cancer iChart..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 6. Ensure app is ready (handle potential crash/reload)
if ! pidof com.liverpooluni.ichartoncology > /dev/null; then
    echo "App failed to start, retrying..."
    monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

echo "=== Setup complete ==="