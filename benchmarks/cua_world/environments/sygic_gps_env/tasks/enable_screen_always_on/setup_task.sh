#!/system/bin/sh
echo "=== Setting up enable_screen_always_on task ==="

PACKAGE="com.sygic.aura"
TASK_DIR="/sdcard/tasks/enable_screen_always_on"
ARTIFACTS_DIR="/sdcard/task_artifacts"

mkdir -p "$ARTIFACTS_DIR"
rm -rf "$ARTIFACTS_DIR/*"

# 1. Record task start time
date +%s > "$ARTIFACTS_DIR/task_start_time.txt"

# 2. Force stop app to ensure clean state
am force-stop $PACKAGE
sleep 2

# 3. Ensure the setting is OFF (Default state)
# We back up and try to modify shared_prefs if they exist
PREFS_DIR="/data/data/$PACKAGE/shared_prefs"
TEMP_PREFS="/data/local/tmp/sygic_prefs_backup"

if [ -d "$PREFS_DIR" ]; then
    echo "Backing up preferences..."
    rm -rf "$TEMP_PREFS"
    mkdir -p "$TEMP_PREFS"
    cp "$PREFS_DIR/"*.xml "$TEMP_PREFS/" 2>/dev/null
    
    # Calculate initial checksums
    md5sum "$PREFS_DIR/"*.xml > "$ARTIFACTS_DIR/initial_prefs_checksums.txt" 2>/dev/null
    
    # Attempt to force disable any screen-on settings in known config files
    # Note: Sygic settings keys vary by version, so we try common patterns
    for xml in "$PREFS_DIR/"*.xml; do
        if [ -f "$xml" ]; then
            # Replace true with false for likely keys
            sed -i 's/name="keep_screen_on" value="true"/name="keep_screen_on" value="false"/g' "$xml"
            sed -i 's/name="screenOn" value="true"/name="screenOn" value="false"/g' "$xml"
            sed -i 's/name="prevent_sleep" value="true"/name="prevent_sleep" value="false"/g' "$xml"
        fi
    done
    
    # Restore ownership/context if needed (usually handled by Android automatically for /data/data but good to be safe)
    # Finding the app's UID
    UID=$(dumpsys package $PACKAGE | grep userId | head -1 | cut -d= -f2 | tr -d ' ')
    if [ -n "$UID" ]; then
        chown -R $UID:$UID "$PREFS_DIR"
    fi
fi

# 4. Launch Sygic GPS Navigation
echo "Launching Sygic..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 15

# 5. Dismiss any startup dialogs/popups
# Close "Map is ready" sheet if present
input tap 860 1510
sleep 2
# Press Back once just in case a menu is open
input keyevent KEYCODE_BACK
sleep 1

# 6. Take initial screenshot
screencap -p "$ARTIFACTS_DIR/initial_state.png"

echo "=== Setup complete ==="