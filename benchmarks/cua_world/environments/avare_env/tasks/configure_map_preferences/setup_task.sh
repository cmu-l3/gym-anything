#!/system/bin/sh
echo "=== Setting up configure_map_preferences task ==="

# Define paths
PACKAGE="com.ds.avare"
PREFS_DIR="/data/data/$PACKAGE/shared_prefs"
PREFS_FILE="$PREFS_DIR/com.ds.avare_preferences.xml"
TASK_DIR="/sdcard/tasks/configure_map_preferences"
TEMP_DIR="/sdcard/task_tmp"

mkdir -p "$TEMP_DIR"

# 1. Record task start time (for anti-gaming)
date +%s > "$TEMP_DIR/task_start_time.txt"

# 2. Force stop app to ensure clean state and file flushing
am force-stop $PACKAGE
sleep 2

# 3. Snapshot initial preferences (if they exist)
# We use cat via su to ensure we can read protected app data
echo "Recording initial preferences state..."
if su 0 ls "$PREFS_FILE" > /dev/null 2>&1; then
    su 0 cat "$PREFS_FILE" > "$TEMP_DIR/initial_prefs.xml"
    su 0 md5sum "$PREFS_FILE" | awk '{print $1}' > "$TEMP_DIR/initial_prefs_hash.txt"
else
    echo "No initial preferences found (fresh state)"
    echo "NONE" > "$TEMP_DIR/initial_prefs_hash.txt"
    echo "" > "$TEMP_DIR/initial_prefs.xml"
fi

# 4. Launch Avare
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# 5. Wait for app to load
sleep 8

# 6. Ensure we are on the main screen (dismiss any startup tips if they appear)
# Tapping back usually dismisses dialogs or closes menus
input keyevent KEYCODE_BACK
sleep 1

# 7. Take initial screenshot
screencap -p "$TEMP_DIR/task_initial.png"

echo "=== Setup complete ==="