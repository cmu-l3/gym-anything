#!/system/bin/sh
# Setup for resonant_frequency_lc task

echo "=== Setting up resonant_frequency_lc task ==="

# Define paths
TASK_DIR="/sdcard/tasks/resonant_frequency_lc"
START_TIME_FILE="$TASK_DIR/task_start_time.txt"
RESULT_FILE="$TASK_DIR/result.txt"
PACKAGE="com.hsn.electricalcalculations"

# Create task directory
mkdir -p "$TASK_DIR"

# Clean up previous run artifacts
rm -f "$RESULT_FILE"
rm -f "$TASK_DIR/result.json"
rm -f "$TASK_DIR/final_state.png"

# Record task start time for anti-gaming verification
date +%s > "$START_TIME_FILE"

# Ensure clean state for the app
echo "Force stopping app..."
am force-stop $PACKAGE 2>/dev/null || true
sleep 2

# Launch the app to main menu
echo "Launching Electrical Calculations..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 6

# Dismiss potential initial dialogs/ads
input keyevent KEYCODE_BACK
sleep 1

# Relaunch to ensure we are at the main activity
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 2

# Take initial screenshot for evidence
screencap -p "$TASK_DIR/initial_state.png" 2>/dev/null || true

echo "=== Setup complete ==="