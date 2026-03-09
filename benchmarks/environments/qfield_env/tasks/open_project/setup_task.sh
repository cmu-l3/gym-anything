#!/system/bin/sh
# Setup script for open_project task.
# Starts QField at the home screen so agent can open the project file.

echo "=== Setting up open_project task ==="

PACKAGE="ch.opengis.qfield"

# Force stop for clean state
am force-stop $PACKAGE
sleep 2

# Ensure the GeoPackage file is in QField's app storage (visible in file browser)
if [ ! -f /sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg ]; then
    echo "GeoPackage missing, copying from mounted data..."
    mkdir -p /sdcard/Android/data/ch.opengis.qfield/files
    cp /sdcard/QFieldData/world_survey.gpkg /sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg
    chmod 644 /sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg
fi

# Press Home
input keyevent KEYCODE_HOME
sleep 1

# Launch QField to the home screen
echo "Launching QField..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# Verify app is in foreground
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher"; then
    echo "App not in foreground, relaunching..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 8
fi

echo "=== open_project task setup complete ==="
echo "QField should be showing the home screen."
echo "Agent should: tap 'OPEN LOCAL PROJECT' -> tap 'QField files directory' -> tap world_survey.gpkg"
