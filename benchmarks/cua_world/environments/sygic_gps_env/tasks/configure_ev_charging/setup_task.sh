#!/system/bin/sh
# Setup script for configure_ev_charging task
# Runs inside the Android environment

echo "=== Setting up configure_ev_charging task ==="

PACKAGE="com.sygic.aura"
TASK_DIR="/sdcard/tasks/configure_ev_charging"
PREFS_DIR="/data/data/$PACKAGE/shared_prefs"

# Ensure task dir exists for artifacts
mkdir -p "$TASK_DIR/artifacts"

# 1. Record Start Time
date +%s > "$TASK_DIR/artifacts/start_time.txt"

# 2. Reset App State (Force Stop)
# We don't clear data completely to avoid re-downloading maps, 
# but we force stop to ensure a clean start.
am force-stop $PACKAGE
sleep 2

# 3. Snapshot Initial Preferences (for diffing later)
# We copy them to a temp location. Requires root access (shell usually has it in this env).
if [ -d "$PREFS_DIR" ]; then
    mkdir -p "$TASK_DIR/artifacts/initial_prefs"
    cp "$PREFS_DIR/"*.xml "$TASK_DIR/artifacts/initial_prefs/" 2>/dev/null
    chmod 777 "$TASK_DIR/artifacts/initial_prefs/"*.xml 2>/dev/null
    echo "Initial preferences backed up."
else
    echo "Warning: Prefs dir not found (app might be fresh)."
fi

# 4. Launch Sygic
echo "Launching Sygic GPS Navigation..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# 5. Wait for App to Load
sleep 10
# Check if running
if pidof "$PACKAGE" > /dev/null; then
    echo "Sygic is running."
else
    echo "Sygic failed to start, retrying..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 10
fi

# 6. Go to Home (Map) Screen
# Send a few back keys to dismiss any lingering dialogs/menus from previous sessions
input keyevent KEYCODE_BACK
sleep 1
input keyevent KEYCODE_BACK
sleep 1

echo "=== Setup Complete ==="