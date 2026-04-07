#!/system/bin/sh
# Setup script for check_antibiotic_interaction_with_venetoclax
# Runs on Android device

echo "=== Setting up task ==="

PACKAGE="com.liverpooluni.ichartoncology"
TASK_DIR="/sdcard/tasks/check_antibiotic_interaction_with_venetoclax"

# 1. Create task directory
mkdir -p "$TASK_DIR"
chmod 777 "$TASK_DIR"

# 2. Clean up previous artifacts
rm -f "$TASK_DIR/result.txt"
rm -f /sdcard/task_result.json

# 3. Record start time (using date +%s if available, else touch a marker file)
date +%s > "$TASK_DIR/start_time.txt" 2>/dev/null || touch "$TASK_DIR/start_marker"

# 4. Ensure App is running and in clean state
echo "Force stopping app..."
am force-stop $PACKAGE
sleep 2

echo "Launching Cancer iChart..."
. /sdcard/scripts/launch_helper.sh
launch_cancer_ichart
# 5. Handle potential startup dialogs (e.g. 'Get Interaction Data')
# The environment setup script handles the initial download, but we ensure it's dismissed here
# Tap generic 'OK' coordinates just in case: [815, 1403]
input tap 815 1403 2>/dev/null
sleep 2

# 6. Ensure we are at the Home/Welcome screen or Cancer Drug list
# If the app remembers state, we might need to back out.
# Sending back key a couple of times is a safe heuristic if stuck in a sub-menu
input keyevent 4 # Back
sleep 1
input keyevent 4 # Back
sleep 1

# Relaunch to ensure foreground
launch_cancer_ichart

# 7. Tap 'Search For Drug Interactions' if on Welcome screen
# Coordinates approx middle of screen or use heuristics.
# Assuming the app opens to the Welcome menu where user taps "Start" or "Search"
# If it opens directly to list, this tap might select a drug, so we skip blind tapping.
# The prompt implies the app starts ready to browse.

echo "=== Task setup complete ==="