#!/system/bin/sh
# Setup script for designate_mesh_hub task.
# Inserts a cluster of 5 sensor nodes into the GeoPackage and starts QField.

echo "=== Setting up designate_mesh_hub task ==="

PACKAGE="ch.opengis.qfield"
SRC_GPKG="/sdcard/QFieldData/world_survey.gpkg"
TASK_GPKG="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"

# Record task start time
date +%s > /sdcard/task_start_time.txt

# ensure directory exists
mkdir -p /sdcard/Android/data/ch.opengis.qfield/files

# Copy fresh GeoPackage
cp "$SRC_GPKG" "$TASK_GPKG"
chmod 666 "$TASK_GPKG"

echo "Inserting sensor node cluster into GeoPackage..."

# Hex blobs for 5 points (SRID 4326)
# Center: 149.13, -35.20
# NW: 149.12, -35.19 (North is positive Y, but here coords are negative, so -35.19 > -35.20)
# NE: 149.14, -35.19
# SW: 149.12, -35.21
# SE: 149.14, -35.21

# SQL Transaction to insert points
# Try 'notes' column first, fallback to 'description' if needed (though we assume 'notes' exists based on environment)
sqlite3 "$TASK_GPKG" <<EOF
BEGIN TRANSACTION;
INSERT INTO field_observations (name, notes, geom) VALUES ('Sensor Node', 'Unassigned', X'47500001E610000001010000005C8FC2F528A462409A999999999941C0');
INSERT INTO field_observations (name, notes, geom) VALUES ('Sensor Node', 'Unassigned', X'47500001E61000000101000000A4703D0AD7A36240B91E85EB519841C0');
INSERT INTO field_observations (name, notes, geom) VALUES ('Sensor Node', 'Unassigned', X'47500001E6100000010100000014AE47E17AA46240B91E85EB519841C0');
INSERT INTO field_observations (name, notes, geom) VALUES ('Sensor Node', 'Unassigned', X'47500001E61000000101000000A4703D0AD7A362407B14AE47E19A41C0');
INSERT INTO field_observations (name, notes, geom) VALUES ('Sensor Node', 'Unassigned', X'47500001E6100000010100000014AE47E17AA462407B14AE47E19A41C0');
COMMIT;
EOF

# Verify insertion
COUNT=$(sqlite3 "$TASK_GPKG" "SELECT count(*) FROM field_observations WHERE name='Sensor Node';")
echo "Inserted $COUNT sensor nodes."

# Force stop QField to ensure clean reload
am force-stop $PACKAGE
sleep 2

# Launch QField with the GeoPackage
echo "Launching QField..."
am start -a android.intent.action.VIEW \
    -d "file:///sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null

# Wait for load
sleep 15

# Dismiss any potential dialogs (best effort)
input keyevent KEYCODE_ESCAPE
sleep 1

echo "=== Setup Complete ==="