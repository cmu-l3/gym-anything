#!/system/bin/sh
# Setup script for lumens_to_candela task
# Runs on Android device

echo "=== Setting up lumens_to_candela task ==="

TASK_DIR="/sdcard/tasks/lumens_to_candela"
PACKAGE="com.hsn.electricalcalculations"

# 1. Create task directory
mkdir -p "$TASK_DIR"
rm -f "$TASK_DIR/result.txt"
rm -f "$TASK_DIR/screenshot.png"
rm -f "$TASK_DIR/task_result.json"

# 2. Record start timestamp (seconds)
date +%s > "$TASK_DIR/start_time.txt"

# 3. Ensure clean app state
echo "Force stopping app..."
am force-stop $PACKAGE
sleep 2

# 4. Launch app to main menu
echo "Launching app..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 5. Dismiss any potential startup dialogs/ads
# Press Back once just in case of an ad overlay
input keyevent KEYCODE_BACK
sleep 1

# Ensure we are not on home screen (re-launch if needed)
CURRENT_FOCUS=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT_FOCUS" | grep -q "Launcher"; then
    echo "Relaunching app..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 3
fi

# 6. Take initial screenshot for evidence
screencap -p "$TASK_DIR/initial_state.png"

echo "=== Setup complete ==="