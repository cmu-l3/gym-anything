#!/system/bin/sh
# Post-task script for crop_pest_scouting.
# Force-stops QField to flush SQLite WAL, then copies the GeoPackage to /sdcard/
# so the verifier can access it via copy_from_env without app-directory restrictions.

echo "=== Post-task cleanup for crop_pest_scouting ==="

PACKAGE="ch.opengis.qfield"
GPKG_APP="/sdcard/Android/data/ch.opengis.qfield/files/crop_pest_scouting.gpkg"
GPKG_OUT="/sdcard/crop_pest_scouting_result.gpkg"

# Force-stop QField to checkpoint SQLite WAL and release file lock
echo "Force-stopping QField..."
am force-stop $PACKAGE
sleep 3

# Copy to /sdcard/ for reliable access by verifier
if [ -f "$GPKG_APP" ]; then
    cp "$GPKG_APP" "$GPKG_OUT"
    chmod 644 "$GPKG_OUT"
    echo "Result GeoPackage copied to: $GPKG_OUT"
    ls -la "$GPKG_OUT"
else
    echo "ERROR: GeoPackage not found at $GPKG_APP"
    exit 1
fi

echo "=== crop_pest_scouting post-task complete ==="
