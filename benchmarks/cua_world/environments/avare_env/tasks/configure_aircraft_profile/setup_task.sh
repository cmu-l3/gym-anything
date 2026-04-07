#!/system/bin/sh
set -e
echo "=== Setting up configure_aircraft_profile task ==="

# Define paths
PACKAGE="com.ds.avare"
PREFS_DIR="/data/data/$PACKAGE/shared_prefs"
TMP_DIR="/data/local/tmp"

# Record task start time for anti-gaming verification
date +%s > "$TMP_DIR/task_start_time.txt"

# Snapshot initial SharedPreferences state (to detect changes later)
# We copy them to a temp location to compare against later
rm -rf "$TMP_DIR/avare_prefs_initial"
mkdir -p "$TMP_DIR/avare_prefs_initial"

if [ -d "$PREFS_DIR" ]; then
    # Copy all xml files
    cp "$PREFS_DIR"/*.xml "$TMP_DIR/avare_prefs_initial/" 2>/dev/null || true
    echo "Initial preferences snapshot saved."
else
    echo "Note: No existing preferences found to snapshot."
fi

# Ensure Avare is not running initially to force a clean start state
am force-stop $PACKAGE
sleep 2

# Launch Avare to the main activity
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# Wait for app to load
sleep 8

# Handle potentially blocking "Required Data" dialog if it appears
# (Pressing Back usually dismisses dialogs without quitting if on main screen)
input keyevent KEYCODE_BACK
sleep 1

# Ensure we are in a clean state (Map View)
# We can't easily verify exact UI element existence with shell only reliably 
# without uiautomator, but we assume launch+back gets us close.

# Take initial screenshot for evidence
screencap -p "$TMP_DIR/task_initial.png"

echo "=== Task setup complete ==="