#!/system/bin/sh
echo "=== Setting up set_track_up_orientation task ==="

# 1. Timestamp for anti-gaming (using date +%s)
date +%s > /sdcard/task_start_time.txt

# 2. Ensure Avare is in a known state (North Up)
PACKAGE="com.ds.avare"
PREFS_FILE="/data/data/com.ds.avare/shared_prefs/com.ds.avare_preferences.xml"

# Force stop to ensure we can modify prefs safely
am force-stop $PACKAGE
sleep 2

# Reset 'TrackUp' preference to false (North Up) if it exists
# We use a temporary file approach because sed -i might behave differently on Android toybox
if [ -f "$PREFS_FILE" ]; then
    echo "Resetting preferences to North Up..."
    # Read file, replace TrackUp="true" with TrackUp="false", write back
    cat "$PREFS_FILE" | sed 's/name="TrackUp" value="true"/name="TrackUp" value="false"/g' > /sdcard/temp_prefs.xml
    
    # Copy back to protected directory (requires root/su)
    cp /sdcard/temp_prefs.xml "$PREFS_FILE"
    chmod 660 "$PREFS_FILE"
    # Ensure ownership is correct (usually u0_aXX:u0_aXX, but generic 'app' user often sufficient if permissions open)
    # On many emulators, just writing it is enough if we run as root.
    rm /sdcard/temp_prefs.xml
else
    echo "Preferences file not found, will be created on launch."
fi

# 3. Launch App
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# 4. Ensure we are on Map screen (dismiss any potential dialogs)
input keyevent KEYCODE_BACK
sleep 1

# 5. Take initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="