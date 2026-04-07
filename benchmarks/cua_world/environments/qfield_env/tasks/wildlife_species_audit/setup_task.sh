#!/system/bin/sh
# Setup script for wildlife_species_audit task.
# Copies wildlife_species_audit.gpkg (writable) and launches QField with it.

echo "=== Setting up wildlife_species_audit task ==="

PACKAGE="ch.opengis.qfield"
GPKG_SRC="/sdcard/QFieldData/wildlife_species_audit.gpkg"
GPKG_TASK="/sdcard/Android/data/ch.opengis.qfield/files/wildlife_species_audit.gpkg"

am force-stop $PACKAGE
sleep 2

echo "Creating writable copy of wildlife_species_audit GeoPackage..."
mkdir -p /sdcard/Android/data/ch.opengis.qfield/files
cp "$GPKG_SRC" "$GPKG_TASK"
chmod 666 "$GPKG_TASK"
echo "GeoPackage ready at $GPKG_TASK"

input keyevent KEYCODE_HOME
sleep 1

echo "Launching QField with wildlife_species_audit.gpkg..."
am start -a android.intent.action.VIEW \
    -d "file:///sdcard/Android/data/ch.opengis.qfield/files/wildlife_species_audit.gpkg" \
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
echo "=== wildlife_species_audit task setup complete ==="
echo "QField has wildlife_species_audit.gpkg open (editable)."
echo "Agent must: identify species with wrong IUCN status -> edit records -> add priority notes -> save"
