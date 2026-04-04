#!/system/bin/sh
# Setup script for add_survey_point task.
# Opens QField with a COPY of world_survey.gpkg (writable) and enables digitizing mode.

echo "=== Setting up add_survey_point task ==="

PACKAGE="ch.opengis.qfield"
GPKG_SRC="/sdcard/QFieldData/world_survey.gpkg"
GPKG_TASK="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"

# Force stop
am force-stop $PACKAGE
sleep 2

# Create a fresh writable copy of the GeoPackage for this task
# This ensures a clean state with no leftover edits
echo "Creating fresh writable copy of GeoPackage..."
mkdir -p /sdcard/Android/data/ch.opengis.qfield/files
cp "$GPKG_SRC" "$GPKG_TASK"
chmod 666 "$GPKG_TASK"
echo "GeoPackage ready at $GPKG_TASK"

# Press Home
input keyevent KEYCODE_HOME
sleep 1

# Launch QField with the GeoPackage
echo "Launching QField with world_survey.gpkg (editable)..."
am start -a android.intent.action.VIEW \
    -d "file:///sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null

sleep 3
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher\|NoActivity"; then
    echo "Intent failed, launching via monkey..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 8
else
    sleep 14
fi

sleep 3

# Pan map toward Africa/Europe to show field_observations data (distinct view from default)
# Pan slightly right to show Europe/Africa region clearly
echo "Panning map to show Africa/Europe with field observation markers..."
input swipe 600 1200 400 1200 400
sleep 2

echo "=== add_survey_point task setup complete ==="
echo "QField has world_survey.gpkg open (editable) with field_observations layer."
echo "Agent should: enable digitizing for field_observations layer -> tap map to add point -> fill form -> save"
