#!/system/bin/sh
# Setup script for generate_sar_pattern task

echo "=== Setting up SAR Pattern Task ==="

PACKAGE="com.ds.avare"
TASK_DIR="/sdcard/tasks/generate_sar_pattern"
mkdir -p "$TASK_DIR"

# Record task start timestamp
date +%s > "$TASK_DIR/task_start_time.txt"

# 1. Force stop Avare to ensure clean state
echo "Stopping Avare..."
am force-stop "$PACKAGE"
sleep 2

# 2. Clear existing flight plan database to ensure start from empty/clean state
#    Avare stores the active plan in plans.db. Deleting it forces Avare to recreate an empty one.
DB_PATH="/data/data/$PACKAGE/databases/plans.db"
DB_JOURNAL="/data/data/$PACKAGE/databases/plans.db-journal"

echo "Clearing active flight plan..."
if [ -f "$DB_PATH" ]; then
    rm "$DB_PATH"
fi
if [ -f "$DB_JOURNAL" ]; then
    rm "$DB_JOURNAL"
fi

# 3. Launch Avare
echo "Launching Avare..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# 4. Handle any 'What's New' or startup dialogs if they appear (simple tap on screen center)
#    Center of 1080x2400 is 540x1200
input tap 540 1200
sleep 1

# 5. Ensure we are on the Map tab (usually the default, but good to be safe)
#    Assuming standard Avare UI, Map is usually the first tab or main view.
#    We'll rely on the default launch state being the Map.

# 6. Capture initial state screenshot
screencap -p "$TASK_DIR/initial_state.png"

echo "=== Task Setup Complete ==="