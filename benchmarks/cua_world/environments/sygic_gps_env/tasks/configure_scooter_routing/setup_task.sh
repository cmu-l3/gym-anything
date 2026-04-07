#!/system/bin/sh
echo "=== Setting up configure_scooter_routing task ==="

PACKAGE="com.sygic.aura"
TASK_DIR="/sdcard/tasks/configure_scooter_routing"
PREFS_DIR="/data/data/$PACKAGE/shared_prefs"

# 1. Record start timestamp for anti-gaming
date +%s > "$TASK_DIR/task_start_time.txt"

# 2. Kill app to ensure clean state
am force-stop $PACKAGE
sleep 1

# 3. Snapshot initial preferences (requires root/su)
# We try to copy them to sdcard to compare later
mkdir -p "$TASK_DIR/artifacts/initial"
if [ -d "$PREFS_DIR" ]; then
    # We use 'su' to access protected data directory
    su 0 cp -r "$PREFS_DIR/." "$TASK_DIR/artifacts/initial/" 2>/dev/null || echo "Warning: Could not snapshot prefs (no root?)"
    chmod -R 777 "$TASK_DIR/artifacts/initial" 2>/dev/null
else
    echo "Warning: Prefs dir not found"
fi

# 4. Launch Application
echo "Launching Sygic GPS..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# 5. Wait for app to load
sleep 10
input keyevent KEYCODE_HOME
sleep 1
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

echo "=== Setup complete ==="