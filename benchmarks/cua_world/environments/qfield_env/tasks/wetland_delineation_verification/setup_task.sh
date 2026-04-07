#!/system/bin/sh
# Setup script for wetland_delineation_verification task.

echo "=== Setting up wetland_delineation_verification task ==="

PACKAGE="ch.opengis.qfield"
GPKG_SRC="/sdcard/QFieldData/wetland_delineation_verification.gpkg"
GPKG_TASK="/sdcard/Android/data/ch.opengis.qfield/files/wetland_delineation_verification.gpkg"

am force-stop $PACKAGE
sleep 2

# Remove stale result files from previous runs
rm -f /sdcard/wetland_delineation_verification_result.gpkg 2>/dev/null

echo "Creating writable copy of wetland_delineation_verification GeoPackage..."
mkdir -p /sdcard/Android/data/ch.opengis.qfield/files
cp "$GPKG_SRC" "$GPKG_TASK"
chmod 666 "$GPKG_TASK"
echo "GeoPackage ready at $GPKG_TASK"

input keyevent KEYCODE_HOME
sleep 1

echo "Launching QField with wetland_delineation_verification.gpkg..."
. /sdcard/scripts/launch_helper.sh
launch_qfield_project "$GPKG_TASK"
echo "=== wetland_delineation_verification task setup complete ==="
echo "Agent must: read soil_borings per wetland -> classify CONFIRMED/REJECTED -> update attributes -> create verification_results for rejected -> identify primary_reference -> save"
