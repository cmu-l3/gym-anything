#!/system/bin/sh
# Setup script for enable_parking_reminder task

echo "=== Setting up Parking Reminder Task ==="

PACKAGE="com.sygic.aura"
TASK_DIR="/sdcard/tasks/enable_parking_reminder"
mkdir -p "$TASK_DIR"

# 1. Record Start Time
date +%s > "$TASK_DIR/start_time.txt"

# 2. Snapshot Initial Preferences (Anti-Gaming)
# We search for parking-related keys in shared_prefs to establish a baseline.
# Note: Requires root or run-as access. We try 'su' first.
echo "Snapshotting initial preferences..."
PREFS_DIR="/data/data/$PACKAGE/shared_prefs"

# Create a safe copy of relevant prefs
su 0 cp -r "$PREFS_DIR" "$TASK_DIR/initial_prefs" 2>/dev/null || true
chmod -R 777 "$TASK_DIR/initial_prefs" 2>/dev/null || true

# Extract specific parking lines for easier comparison
grep -r -i "park" "$TASK_DIR/initial_prefs" > "$TASK_DIR/initial_parking_state.txt" 2>/dev/null || echo "No initial parking prefs found" > "$TASK_DIR/initial_parking_state.txt"

echo "Initial state:"
cat "$TASK_DIR/initial_parking_state.txt"

# 3. Ensure App is Clean and Ready
echo "Restarting Sygic..."
am force-stop $PACKAGE
sleep 2

# Launch to main activity
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# 4. Handle any "Welcome back" or startup sheets
# Tap generic center/bottom area just in case a sheet is up
input tap 860 1510
sleep 2

# Capture initial screenshot
screencap -p "$TASK_DIR/initial_state.png"

echo "=== Setup Complete ==="