#!/system/bin/sh
set -e
echo "=== Setting up digitize_cable_route task ==="

# Define paths
PACKAGE="ch.opengis.qfield"
DATA_DIR="/sdcard/Android/data/ch.opengis.qfield/files"
GPKG_SOURCE="/sdcard/QFieldData/world_survey.gpkg"
GPKG_DEST="$DATA_DIR/Imported Datasets/world_survey.gpkg"

# Record task start time
date +%s > /sdcard/task_start_time.txt

# Ensure QField is stopped
am force-stop $PACKAGE 2>/dev/null || true
sleep 2

# Ensure directory structure exists
mkdir -p "$DATA_DIR/Imported Datasets"

# Reset GeoPackage to clean state from source
# We copy it to the writable location
cp "$GPKG_SOURCE" "$GPKG_DEST"
chmod 666 "$GPKG_DEST"

# Prepare the SQL to create the cable_routes layer if it doesn't exist
# We do this manually via sqlite3 since the agent needs an existing layer to edit
echo "Creating cable_routes layer in GeoPackage..."
sqlite3 "$GPKG_DEST" <<'EOSQL'
-- Create table
CREATE TABLE IF NOT EXISTS cable_routes (
    fid INTEGER PRIMARY KEY AUTOINCREMENT,
    geom BLOB,
    route_name TEXT,
    cable_type TEXT,
    notes TEXT
);

-- Register in gpkg_contents
INSERT OR REPLACE INTO gpkg_contents (table_name, data_type, identifier, description, last_change, min_x, min_y, max_x, max_y, srs_id)
VALUES ('cable_routes', 'features', 'Cable Routes', 'Planned fiber optic routes', strftime('%Y-%m-%dT%H:%M:%fZ','now'), -180, -90, 180, 90, 4326);

-- Register in gpkg_geometry_columns
INSERT OR REPLACE INTO gpkg_geometry_columns (table_name, column_name, geometry_type_name, srs_id, z, m)
VALUES ('cable_routes', 'geom', 'LINESTRING', 4326, 0, 0);
EOSQL

# Record initial row count (should be 0)
INITIAL_COUNT=$(sqlite3 "$GPKG_DEST" "SELECT count(*) FROM cable_routes;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /sdcard/initial_count.txt

# Go to Home screen
input keyevent KEYCODE_HOME
sleep 1

# Launch QField directly opening the project
# This saves the agent from navigating the file picker which can be flaky in emulators
echo "Launching QField..."
am start -a android.intent.action.VIEW \
    -d "file://$GPKG_DEST" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null

# Wait for app to load
sleep 10

# Tap "Center on GPS" or dismiss any location warnings if they appear
# (Optional, depending on emulator state)

echo "=== Task setup complete ==="