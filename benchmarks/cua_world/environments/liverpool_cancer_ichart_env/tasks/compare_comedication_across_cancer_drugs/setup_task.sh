#!/system/bin/sh
echo "=== Setting up compare_comedication_across_cancer_drugs task ==="

PACKAGE="com.liverpooluni.ichartoncology"
REPORT_DIR="/sdcard/Download"
REPORT_FILE="$REPORT_DIR/clarithromycin_comparison.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"

# 1. Prepare environment
mkdir -p "$REPORT_DIR"
# Remove any existing report to prevent false positives
rm -f "$REPORT_FILE"

# 2. Record task start time (using standard Unix timestamp)
date +%s > "$START_TIME_FILE"
echo "Task start time recorded: $(cat $START_TIME_FILE)"

# 3. Ensure clean app state
echo "Force stopping Cancer iChart..."
am force-stop "$PACKAGE"
sleep 1

# 4. Launch Application to Main Activity
echo "Launching Cancer iChart..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 5. Handle potential startup state (ensure we are at a usable screen)
# We assume the environment setup (setup_cancer_ichart.sh) handled the initial DB download.
# Just in case, we wait a bit to ensure the UI is loaded.
sleep 3

# 6. Capture initial state evidence
screencap -p /sdcard/task_initial_state.png

echo "=== Task setup complete ==="