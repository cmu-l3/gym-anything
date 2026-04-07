#!/system/bin/sh
set -e
echo "=== Setting up digitize_star_network task ==="

# Define paths
PACKAGE="ch.opengis.qfield"
SOURCE_GPKG="/sdcard/QFieldData/world_survey.gpkg"
DEST_DIR="/sdcard/Android/data/ch.opengis.qfield/files"
WORK_GPKG="$DEST_DIR/world_survey.gpkg"

# 1. Kill QField to release file locks
am force-stop $PACKAGE
sleep 2

# 2. Prepare the directory and copy fresh GeoPackage
mkdir -p "$DEST_DIR"
cp "$SOURCE_GPKG" "$WORK_GPKG"
chmod 666 "$WORK_GPKG"

# 3. Add the 'network_lines' layer using sqlite3
# This simulates the "Network Planning" project state
echo "Creating network_lines layer in GeoPackage..."
sqlite3 "$WORK_GPKG" <<EOF
-- Create table
CREATE TABLE network_lines (
    fid INTEGER PRIMARY KEY AUTOINCREMENT,
    geom LINESTRING,
    link_id TEXT,
    status TEXT
);

-- Register in gpkg_contents
INSERT INTO gpkg_contents (table_name, data_type, identifier, description, last_change, srs_id)
VALUES ('network_lines', 'features', 'network_lines', 'Fiber Network Routes', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), 4326);

-- Register in gpkg_geometry_columns
INSERT INTO gpkg_geometry_columns (table_name, column_name, geometry_type_name, srs_id, z, m)
VALUES ('network_lines', 'geom', 'LINESTRING', 4326, 0, 0);
EOF

# 4. Create timestamp for anti-gaming
date +%s > /sdcard/task_start_time.txt
# Record initial row count (should be 0)
echo "0" > /sdcard/initial_count.txt

# 5. Launch QField with the project
echo "Launching QField..."
# Use VIEW intent to open specific project directly
am start -a android.intent.action.VIEW \
    -d "file://$WORK_GPKG" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity"

# Wait for load
sleep 15

# 6. Capture initial state screenshot (using screencap on Android)
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="