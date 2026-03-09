#!/system/bin/sh
set -e
echo "=== Setting up verify_anticoagulant_safety_with_enzalutamide task ==="

# Define paths
TASK_DIR="/sdcard/tasks/verify_anticoagulant_safety_with_enzalutamide"
mkdir -p "$TASK_DIR"

# Record task start time for anti-gaming verification
date +%s > "$TASK_DIR/task_start_time.txt"

PACKAGE="com.liverpooluni.ichartoncology"

# Ensure app is installed
if ! pm list packages | grep -q "$PACKAGE"; then
    echo "ERROR: Liverpool Cancer iChart not installed"
    exit 1
fi

# Force stop to ensure clean state
echo "Stopping application..."
am force-stop $PACKAGE
sleep 2

# Launch the app
echo "Launching Liverpool Cancer iChart..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 6

# Ensure we are at the start. 
# Sometimes the app remembers the last state. We try to back out to home if needed.
# Since we forced stopped, it usually starts fresh, but let's be safe.
# We expect the 'Cancer Drugs' selection screen or the 'Welcome' screen.
# If on Welcome screen, we might need to tap 'Search'.
# However, the env setup usually leaves it ready. 
# We will assume standard launch state.

# Take initial state screenshot for evidence
screencap -p "$TASK_DIR/initial_state.png"

echo "=== Task setup complete ==="