#!/system/bin/sh
echo "=== Setting up avoid_motorways task ==="

PACKAGE="com.sygic.aura"
TASK_DIR="/sdcard/tasks/avoid_motorways"
DATA_DIR="/sdcard/task_data"

# Create data directory for evidence
mkdir -p "$DATA_DIR"
rm -rf "$DATA_DIR/*"

# Record task start time
date +%s > "$DATA_DIR/task_start_time.txt"

# 1. Capture INITIAL state of shared preferences (for diffing)
# We need to copy from the protected app directory to sdcard
echo "Capturing initial preferences state..."
mkdir -p "$DATA_DIR/initial_prefs"
# Using 'cp' might fail due to permissions, but usually 'run-as' or root access is available in this env
# If root:
cp -r /data/data/$PACKAGE/shared_prefs/* "$DATA_DIR/initial_prefs/" 2>/dev/null
# Fallback if regular copy fails (try via run-as if available, or assume root)
if [ -z "$(ls -A $DATA_DIR/initial_prefs)" ]; then
    run-as $PACKAGE cp -r /data/data/$PACKAGE/shared_prefs/* "$DATA_DIR/initial_prefs/" 2>/dev/null
fi

# 2. Ensure App is Running and Reset
echo "Restarting Sygic GPS..."
am force-stop $PACKAGE
sleep 2

# Launch the app
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# 3. Ensure we are on the map screen (basic heuristic)
# We can't easily guarantee this without coordinates, but a fresh launch usually goes to map
# or shows a "Resume" dialog. We'll press BACK once just in case a menu was open.
input keyevent KEYCODE_BACK
sleep 1

echo "=== Setup complete ==="