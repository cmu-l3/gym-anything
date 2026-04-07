#!/system/bin/sh
set -e
echo "=== Setting up expand_sanctuary_boundary task ==="

# Define paths
PACKAGE="ch.opengis.qfield"
DATA_DIR="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets"
GPKG_DEST="$DATA_DIR/world_survey.gpkg"
GPKG_SOURCE="/sdcard/QFieldData/world_survey.gpkg"

# 1. Clean up previous state
am force-stop $PACKAGE
sleep 2
mkdir -p "$DATA_DIR"
rm -f "$GPKG_DEST" "$GPKG_DEST-wal" "$GPKG_DEST-shm"

# 2. Start with fresh copy of base GeoPackage
if [ -f "$GPKG_SOURCE" ]; then
    cp "$GPKG_SOURCE" "$GPKG_DEST"
else
    # Fallback if source missing (should not happen in correct env)
    echo "ERROR: Source GeoPackage not found at $GPKG_SOURCE"
    exit 1
fi

# 3. Inject Task Data (Sanctuary Polygon & Water Source Point)
# We use sqlite3 to create tables and insert features manually
# because we need specific geometries not in the base map.

echo "Injecting sanctuary zones and water sources..."

# Create Tables
sqlite3 "$GPKG_DEST" "CREATE TABLE sanctuary_zones (fid INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, geom BLOB);"
sqlite3 "$GPKG_DEST" "CREATE TABLE critical_water_sources (fid INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, geom BLOB);"

# Register in gpkg_contents
# Bounds: 147.30, -42.82 to 147.33, -42.80 (Tasmania)
sqlite3 "$GPKG_DEST" "INSERT INTO gpkg_contents (table_name, data_type, identifier, description, last_change, min_x, min_y, max_x, max_y, srs_id) VALUES ('sanctuary_zones', 'features', 'sanctuary_zones', 'Sanctuary Zones', strftime('%Y-%m-%dT%H:%M:%fZ','now'), 147.30, -42.82, 147.32, -42.80, 4326);"
sqlite3 "$GPKG_DEST" "INSERT INTO gpkg_contents (table_name, data_type, identifier, description, last_change, min_x, min_y, max_x, max_y, srs_id) VALUES ('critical_water_sources', 'features', 'critical_water_sources', 'Critical Water Sources', strftime('%Y-%m-%dT%H:%M:%fZ','now'), 147.33, -42.81, 147.33, -42.81, 4326);"

# Register in gpkg_geometry_columns
sqlite3 "$GPKG_DEST" "INSERT INTO gpkg_geometry_columns (table_name, column_name, geometry_type_name, srs_id, z, m) VALUES ('sanctuary_zones', 'geom', 'POLYGON', 4326, 0, 0);"
sqlite3 "$GPKG_DEST" "INSERT INTO gpkg_geometry_columns (table_name, column_name, geometry_type_name, srs_id, z, m) VALUES ('critical_water_sources', 'geom', 'POINT', 4326, 0, 0);"

# Insert Features (GeoPackage Binary Blob Format)
# Header: Magic(0x4750) + Ver(0) + Flags(1=BinaryEnvelope) + SRS(4326) + Envelope(MinX,MaxX,MinY,MaxY)
# Note: For simplicity in shell script injection, we use Standard GeoPackage Binary format with Little Endian (01)
#
# POLYGON (Triangle): (147.30 -42.80, 147.30 -42.82, 147.32 -42.81, 147.30 -42.80)
# POINT (Water Source): (147.33 -42.81) -> Outside to the East

# Hex Strings constructed for these geometries (Little Endian):
# Sanctuary A (Polygon)
POLY_HEX="47500001E6100000010300000001000000040000009A9999999969624066666666666645C09A99999999696240B81E85EB516945C05C8FC2F5286A62401F85EB51B86745C09A9999999969624066666666666645C0"
sqlite3 "$GPKG_DEST" "INSERT INTO sanctuary_zones (name, geom) VALUES ('Sanctuary A', X'$POLY_HEX');"

# Water Source (Point) - Located at 147.33, -42.81
POINT_HEX="47500001E61000000101000000713D0AD7A36A6240AE47E17A146845C0"
sqlite3 "$GPKG_DEST" "INSERT INTO critical_water_sources (name, geom) VALUES ('Water Source', X'$POINT_HEX');"

# 4. Set permissions
chmod 666 "$GPKG_DEST"

# 5. Record task start time
date +%s > /sdcard/task_start_time.txt

# 6. Launch QField and Open Project
echo "Launching QField..."
# Use VIEW intent to open the file directly
am start -a android.intent.action.VIEW \
    -d "file://$GPKG_DEST" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity"

# Wait for load
sleep 15

# 7. Take initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="