#!/system/bin/sh
# Setup script for enable_cap_grid_overlay task

echo "=== Setting up CAP Grid Overlay Task ==="

PACKAGE="com.ds.avare"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/${PACKAGE}_preferences.xml"
TEMP_PREFS="/data/local/tmp/prefs.xml"

# 1. Force stop the app to ensure we can modify preferences safely
am force-stop $PACKAGE
sleep 2

# 2. Ensure the setting is DISABLED initially
# We need to edit the XML file to set ShowCAP to false or remove it
if [ -f "$PREFS_FILE" ]; then
    echo "Modifying existing preferences..."
    # Copy to temp for editing
    cp "$PREFS_FILE" "$TEMP_PREFS"
    chmod 666 "$TEMP_PREFS"
    
    # Use sed to set ShowCAP to false if it exists
    if grep -q "ShowCAP" "$TEMP_PREFS"; then
        sed -i 's/name="ShowCAP" value="true"/name="ShowCAP" value="false"/g' "$TEMP_PREFS"
    else
        # If it doesn't exist, we don't strictly need to add it as false is default,
        # but let's leave it alone.
        echo "ShowCAP key not found, default is likely false."
    fi
    
    # Copy back
    run-as $PACKAGE cp "$TEMP_PREFS" "$PREFS_FILE" 2>/dev/null || cp "$TEMP_PREFS" "$PREFS_FILE"
    rm "$TEMP_PREFS"
fi

# 3. Record task start time (Unix timestamp)
date +%s > /sdcard/task_start_time.txt

# 4. Launch the application
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# 5. Wait for app to load
sleep 10

# 6. Ensure we are at the home screen (Map)
# Send a BACK key just in case a dialog is open, but usually fresh launch is fine
# input keyevent 4 

echo "=== Setup Complete ==="