#!/system/bin/sh
echo "=== Setting up Enable Auto-Show Diagram Task ==="

# 1. Define variables
PACKAGE="com.ds.avare"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/${PACKAGE}_preferences.xml"
TASK_DIR="/sdcard/tasks/enable_auto_diagram"
TIMESTAMP_FILE="/sdcard/task_start_time.txt"

# 2. Record task start time (for anti-gaming)
date +%s > "$TIMESTAMP_FILE"

# 3. Ensure Avare is clean/installed
if ! pm list packages | grep -q "$PACKAGE"; then
    echo "Error: Avare package not found!"
    exit 1
fi

# 4. Reset specific preference to ensure it is FALSE (Disabled) initially
# We use a temporary sed script to modify the XML if it exists
if [ -f "$PREFS_FILE" ]; then
    echo "Ensuring Auto Show Diagram is disabled..."
    # Copy to tmp, Modify, Copy back (requires root/su)
    cp "$PREFS_FILE" /sdcard/prefs_temp.xml
    # simple sed to set value="false" for any key containing AirportDiagram
    sed -i 's/name=".*AirportDiagram" value="true"/name="ShowAirportDiagram" value="false"/g' /sdcard/prefs_temp.xml
    
    # Copy back with correct permissions
    su 0 cp /sdcard/prefs_temp.xml "$PREFS_FILE"
    su 0 chmod 660 "$PREFS_FILE"
    su 0 chown u0_a$(dumpsys package $PACKAGE | grep userId | cut -d= -f2 | head -1):u0_a$(dumpsys package $PACKAGE | grep userId | cut -d= -f2 | head -1) "$PREFS_FILE"
    rm /sdcard/prefs_temp.xml
fi

# 5. Force stop and launch app to reload preferences
echo "Launching Avare..."
am force-stop $PACKAGE
sleep 2
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1
sleep 8

# 6. dismissal of any "What's New" or startup dialogs if they appear
# (Agent should handle this, but we help ensure main activity is focused)
input keyevent KEYCODE_BACK
sleep 1

# 7. Take initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="