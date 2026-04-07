#!/system/bin/sh
# Post-task script for utility_line_vegetation_clearance_audit.

echo "=== Post-task cleanup for utility_line_vegetation_clearance_audit ==="

PACKAGE="ch.opengis.qfield"
GPKG_APP="/sdcard/Android/data/ch.opengis.qfield/files/utility_line_vegetation_clearance_audit.gpkg"
GPKG_OUT="/sdcard/utility_line_vegetation_clearance_audit_result.gpkg"

echo "Force-stopping QField..."
am force-stop $PACKAGE
sleep 3

if [ -f "$GPKG_APP" ]; then
    cp "$GPKG_APP" "$GPKG_OUT"
    chmod 644 "$GPKG_OUT"
    echo "Result GeoPackage copied to: $GPKG_OUT"
    ls -la "$GPKG_OUT"
else
    echo "ERROR: GeoPackage not found at $GPKG_APP"
    exit 1
fi

echo "=== utility_line_vegetation_clearance_audit post-task complete ==="
