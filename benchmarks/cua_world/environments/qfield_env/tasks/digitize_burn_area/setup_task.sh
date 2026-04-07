#!/system/bin/sh
set -e
echo "=== Setting up digitize_burn_area task ==="

# Record task start time for anti-gaming
date +%s > /sdcard/task_start_time.txt

PACKAGE="ch.opengis.qfield"
GPKG_DIR="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets"
GPKG_PATH="$GPKG_DIR/world_survey.gpkg"
SOURCE_GPKG="/sdcard/QFieldData/world_survey.gpkg"

# Force-stop QField to ensure clean state
am force-stop $PACKAGE 2>/dev/null || true
sleep 2

# Ensure directory exists
mkdir -p "$GPKG_DIR"

# Reset GeoPackage from source
cp "$SOURCE_GPKG" "$GPKG_PATH"
chmod 666 "$GPKG_PATH"

# Add burn_areas polygon layer to the GeoPackage using sqlite3
# We must register it in gpkg_contents and gpkg_geometry_columns for QField to see it
echo "Adding burn_areas polygon layer to GeoPackage..."

sqlite3 "$GPKG_PATH" <<'EOF'
-- Create the burn_areas polygon table
CREATE TABLE IF NOT EXISTS burn_areas (
    fid INTEGER PRIMARY KEY AUTOINCREMENT,
    geom BLOB,
    fire_name TEXT,
    severity TEXT,
    date_observed TEXT,
    area_status TEXT
);

-- Register in gpkg_contents
INSERT OR REPLACE INTO gpkg_contents (table_name, data_type, identifier, description, last_change, min_x, min_y, max_x, max_y, srs_id)
VALUES ('burn_areas', 'features', 'burn_areas', 'Post-fire burn area polygons', datetime('now'), -180, -90, 180, 90, 4326);

-- Register geometry column
INSERT OR REPLACE INTO gpkg_geometry_columns (table_name, column_name, geometry_type_name, srs_id, z, m)
VALUES ('burn_areas', 'geom', 'POLYGON', 4326, 0, 0);
EOF

# Verify the table was created
COUNT=$(sqlite3 "$GPKG_PATH" "SELECT COUNT(*) FROM burn_areas;" 2>/dev/null || echo "ERROR")
echo "burn_areas initial row count: $COUNT"
echo "$COUNT" > /sdcard/initial_burn_area_count.txt

# Launch QField with the GeoPackage directly
echo "Launching QField..."
am start -a android.intent.action.VIEW \
    -d "file://$GPKG_PATH" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null

# Wait for load
sleep 10

# Dismiss any potential tutorials or dialogs
input keyevent KEYCODE_BACK 2>/dev/null || true

# Capture initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="