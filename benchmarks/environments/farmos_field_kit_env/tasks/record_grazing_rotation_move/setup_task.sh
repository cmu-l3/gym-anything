#!/system/bin/sh
# Setup script for record_grazing_rotation_move task
# Clears app data to ensure a clean starting state

echo "=== Setting up Grazing Rotation Task ==="

PACKAGE="org.farmos.app"
TASK_DIR="/sdcard/tasks/record_grazing_rotation_move"
mkdir -p "$TASK_DIR"

# 1. Record start time for anti-gaming (using standard unix timestamp)
date +%s > "$TASK_DIR/task_start_time.txt"

# 2. Reset Application State
echo "Clearing app data for clean state..."
am force-stop $PACKAGE
pm clear $PACKAGE
sleep 2

# 3. Grant Permissions (Location is needed for the map view to work without prompts)
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null

# 4. Launch Application
echo "Launching farmOS Field Kit..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# 5. Wait for app to load
sleep 5

# Ensure we are at the Home/Launcher screen if app failed, or ensure app is focused
# We use dumpsys to check focus
CURRENT_FOCUS=$(dumpsys window | grep -i mCurrentFocus)
echo "Current focus: $CURRENT_FOCUS"

# 6. Capture initial state
screencap -p "$TASK_DIR/initial_state.png"

echo "=== Setup Complete ==="