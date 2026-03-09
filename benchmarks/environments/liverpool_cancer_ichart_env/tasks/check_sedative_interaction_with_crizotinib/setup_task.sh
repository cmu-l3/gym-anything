#!/system/bin/sh
# Setup script for check_sedative_interaction_with_crizotinib
# Runs on Android device

echo "=== Setting up Crizotinib-Midazolam Interaction Task ==="

PACKAGE="com.liverpooluni.ichartoncology"
TASK_DIR="/sdcard/tasks"
START_TIME_FILE="$TASK_DIR/task_start_time.txt"
OUTPUT_FILE="$TASK_DIR/crizotinib_midazolam_result.txt"

# Ensure task directory exists (it should be mounted, but safe to check)
mkdir -p "$TASK_DIR"

# Clean up previous artifacts
rm -f "$OUTPUT_FILE"
rm -f "$TASK_DIR/task_result.json"

# Record start time for anti-gaming verification
date +%s > "$START_TIME_FILE"

# Force stop the app to ensure clean state
am force-stop "$PACKAGE"
sleep 2

# Go to Home screen
input keyevent KEYCODE_HOME
sleep 1

# Launch the app freshly
echo "Launching Cancer iChart..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# Ensure app is in foreground
CURRENT_FOCUS=$(dumpsys window | grep mCurrentFocus)
if ! echo "$CURRENT_FOCUS" | grep -q "$PACKAGE"; then
    echo "App didn't start correctly, trying again..."
    monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

echo "=== Setup Complete ==="