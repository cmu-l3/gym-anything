#!/system/bin/sh
echo "=== Setting up disable_3d_buildings task ==="

# Define writable paths
TASK_DIR="/data/local/tmp/disable_3d_buildings"
mkdir -p "$TASK_DIR"
chmod 777 "$TASK_DIR"

# Record task start time
date +%s > "$TASK_DIR/start_time.txt"

# Package name
PACKAGE="com.sygic.aura"

# Ensure clean state (force stop)
am force-stop $PACKAGE
sleep 2

# Go Home
input keyevent KEYCODE_HOME
sleep 1

# Launch Sygic GPS Navigation
echo "Launching Sygic..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# Wait for app to load
sleep 10

# Ensure we are not stuck on a splash screen or dialog
# Simple check: dumpsys window to see if we are in the main activity
# If not, try to tap the screen center once (dismiss potential 'What's new' sheet)
input tap 540 1200
sleep 1

echo "=== Setup Complete ==="