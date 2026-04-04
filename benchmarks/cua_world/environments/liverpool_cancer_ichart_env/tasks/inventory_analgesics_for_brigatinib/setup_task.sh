#!/system/bin/sh
# Setup script for inventory_analgesics_for_brigatinib task

echo "=== Setting up Inventory Task ==="

# Define paths
OUTPUT_FILE="/sdcard/Download/brigatinib_analgesics_inventory.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
PACKAGE="com.liverpooluni.ichartoncology"

# 1. clean up previous run artifacts
rm -f "$OUTPUT_FILE"
rm -f "$START_TIME_FILE"
rm -f "/sdcard/task_result.json"

# 2. Record start time (using date +%s if available, else a rough marker)
date +%s > "$START_TIME_FILE" 2>/dev/null || echo "0" > "$START_TIME_FILE"

# 3. Ensure app is closed to start from a fresh state
echo "Force stopping Cancer iChart..."
am force-stop "$PACKAGE"
sleep 2

# 4. Launch the app to the home screen (Welcome)
echo "Launching Cancer iChart..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 5. Ensure we are at the home screen (handle any restoration dialogs if they appear, though usually force-stop clears them)
# Just wait a bit to ensure UI is ready
sleep 2

echo "=== Setup Complete ==="
echo "Task: Create inventory of Analgesics for Brigatinib"