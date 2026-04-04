#!/system/bin/sh
echo "=== Setting up Verify Vaccine Safety Profile Task ==="

# 1. Define package and path
PACKAGE="com.liverpooluni.ichartoncology"
OUTPUT_FILE="/sdcard/rituximab_vaccine_report.txt"

# 2. Record start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# 3. Clean up previous artifacts
rm -f "$OUTPUT_FILE" 2>/dev/null
rm -f /sdcard/task_result.json 2>/dev/null

# 4. Ensure device is in a known state (Home screen)
input keyevent KEYCODE_HOME
sleep 1

# 5. Launch the application
echo "Launching Cancer iChart..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 6. Ensure the app is in the foreground
if dumpsys window | grep mCurrentFocus | grep -q "$PACKAGE"; then
    echo "App launched successfully."
else
    echo "App not focused, forcing launch..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

# 7. Take initial screenshot evidence
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="