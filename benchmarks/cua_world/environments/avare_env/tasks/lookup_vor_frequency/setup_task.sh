#!/system/bin/sh
set -e
echo "=== Setting up lookup_vor_frequency task ==="

# Define paths
OUTPUT_FILE="/data/local/tmp/vor_frequency.txt"
START_TIME_FILE="/data/local/tmp/task_start_time.txt"
INITIAL_SCREENSHOT="/data/local/tmp/task_initial.png"
PACKAGE="com.ds.avare"

# 1. Clean up previous artifacts
rm -f "$OUTPUT_FILE"
rm -f "$INITIAL_SCREENSHOT"
rm -f /data/local/tmp/task_result.json

# 2. Record task start time (for anti-gaming verification)
date +%s > "$START_TIME_FILE"

# 3. Ensure Avare is running and clean
# Force stop to ensure fresh state
am force-stop "$PACKAGE" 2>/dev/null || true
sleep 2

# Launch Avare to main activity
echo "Launching Avare..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# Handle potential "Crash" or "Not Responding" dialogs by pressing Back/Enter if needed
# (Optional heuristic)

# 4. Take initial screenshot for evidence
screencap -p "$INITIAL_SCREENSHOT" 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Target: Look up OAK VOR frequency"
echo "Output required at: $OUTPUT_FILE"