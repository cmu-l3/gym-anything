#!/system/bin/sh
# Setup script for recover_null_island_points task.
# Runs inside the Android environment.

echo "=== Setting up recover_null_island_points task ==="

PACKAGE="ch.opengis.qfield"
DATA_DIR="/sdcard/Android/data/ch.opengis.qfield/files"
GPKG_SOURCE="/sdcard/QFieldData/world_survey.gpkg"
GPKG_DEST="$DATA_DIR/world_survey.gpkg"

# 1. Prepare clean data directory
mkdir -p "$DATA_DIR"
rm -f "$GPKG_DEST"
rm -f "$DATA_DIR/world_survey.gpkg-shm"
rm -f "$DATA_DIR/world_survey.gpkg-wal"

# 2. Copy the fresh GeoPackage
echo "Copying GeoPackage..."
cp "$GPKG_SOURCE" "$GPKG_DEST"
chmod 666 "$GPKG_DEST"

# 3. Corrupt the data (Move 3 capitals to Null Island)
# We use a GeoPackage Geometry BLOB for SRID 4326 Point(0 0)
# Hex: 47500001E6100000010100000000000000000000000000000000000000
# (Header: GP, Ver 0, Flags 1 (LittleEndian), SRID 4326, WKB: Point(0 0))

echo "Corrupting coordinates for Caracas, Bogota, and Quito..."
sqlite3 "$GPKG_DEST" <<EOF
UPDATE world_capitals 
SET description = description || ' Original Coords: ' || round(st_y(geom), 2) || ', ' || round(st_x(geom), 2),
    geom = x'47500001E6100000010100000000000000000000000000000000000000'
WHERE name IN ('Caracas', 'Bogota', 'Quito');
EOF

# 4. Verify corruption
COUNT=$(sqlite3 "$GPKG_DEST" "SELECT count(*) FROM world_capitals WHERE ST_X(geom) = 0 AND ST_Y(geom) = 0;")
echo "Number of features at Null Island: $COUNT"

# 5. Record start timestamp
date +%s > /sdcard/task_start_time.txt

# 6. Ensure QField is closed
am force-stop $PACKAGE
sleep 2

# 7. Launch QField to home screen
echo "Launching QField..."
. /sdcard/scripts/launch_helper.sh
launch_qfield_project

echo "=== Setup Complete ==="