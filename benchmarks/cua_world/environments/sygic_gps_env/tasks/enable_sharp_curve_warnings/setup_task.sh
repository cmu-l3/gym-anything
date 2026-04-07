#!/system/bin/sh
# Setup script for enable_sharp_curve_warnings
# Ensures Sygic is running and the specific setting is initially OFF.

echo "=== Setting up enable_sharp_curve_warnings task ==="

PACKAGE="com.sygic.aura"
PREFS_FILE="/data/data/com.sygic.aura/shared_prefs/com.sygic.aura_preferences.xml"
TASK_DIR="/sdcard/tasks/enable_sharp_curve_warnings"

# Create task directory
mkdir -p "$TASK_DIR"

# Record start time for anti-gaming
date +%s > "$TASK_DIR/start_time.txt"

# Force stop to allow modifying prefs
am force-stop $PACKAGE
sleep 2

# Attempt to disable the setting initially (if file exists)
# We look for keys containing 'curve' and set them to false
if [ -f "$PREFS_FILE" ]; then
    echo "Modifying preferences to disable curve warnings..."
    # Note: This is a rough heuristic sed command. 
    # It attempts to change any boolean entry with 'curve' in the name to value="false"
    # Root access is assumed via the environment configuration.
    sed -i 's/\(<boolean name=".*curve.*" value="\)true"/\1false"/I' "$PREFS_FILE"
    
    # Save initial state of prefs for comparison
    cp "$PREFS_FILE" "$TASK_DIR/initial_prefs.xml"
    chmod 666 "$TASK_DIR/initial_prefs.xml"
else
    echo "Preferences file not found, skipping modification."
fi

# Launch app
echo "Launching Sygic GPS Navigation..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# Handle "Your map is ready" or other startup sheets if they appear
# Tap X to close bottom sheet if present (approx coords)
input tap 860 1510
sleep 2

# Ensure we are on the map screen (press back just in case we are in a menu)
input keyevent KEYCODE_BACK
sleep 1

# Take initial screenshot
screencap -p "$TASK_DIR/initial_state.png"

echo "=== Setup complete ==="