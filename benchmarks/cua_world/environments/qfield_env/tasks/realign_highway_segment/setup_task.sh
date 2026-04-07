#!/system/bin/sh
# setup_task.sh for realign_highway_segment
# Prepares the GeoPackage with a highway_segments layer containing a straight line.

echo "=== Setting up realign_highway_segment task ==="

PACKAGE="ch.opengis.qfield"
DATA_DIR="/sdcard/Android/data/ch.opengis.qfield/files"
IMPORT_DIR="$DATA_DIR/Imported Datasets"
GPKG="$IMPORT_DIR/world_survey.gpkg"
SOURCE_GPKG="/sdcard/QFieldData/world_survey.gpkg"

# Record start time
date +%s > /data/local/tmp/task_start_time.txt

# 1. Prepare Directory
mkdir -p "$IMPORT_DIR"

# 2. Copy fresh GeoPackage
# We copy from source to ensure we have the capitals layer, then we inject our new layer
if [ -f "$SOURCE_GPKG" ]; then
    cp "$SOURCE_GPKG" "$GPKG"
else
    # Fallback if source missing (should not happen in this env)
    echo "Error: Source GeoPackage not found at $SOURCE_GPKG"
    exit 1
fi
chmod 666 "$GPKG"

# 3. Inject 'highway_segments' layer via sqlite3
# We create the table and metadata entries manually since we don't have OGR/GDAL in the android shell.

# Create Table
sqlite3 "$GPKG" "CREATE TABLE highway_segments (fid INTEGER PRIMARY KEY AUTOINCREMENT, geom LINESTRING, name TEXT, type TEXT);"

# Register in gpkg_contents
sqlite3 "$GPKG" "INSERT INTO gpkg_contents (table_name, data_type, identifier, description, last_change, min_x, min_y, max_x, max_y, srs_id) VALUES ('highway_segments', 'features', 'highway_segments', 'Highway Segments', strftime('%Y-%m-%dT%H:%M:%fZ','now'), 2.0, 6.0, 4.0, 37.0, 4326);"

# Register in gpkg_geometry_columns
sqlite3 "$GPKG" "INSERT INTO gpkg_geometry_columns (table_name, column_name, geometry_type_name, srs_id, z, m) VALUES ('highway_segments', 'geom', 'LINESTRING', 4326, 0, 0);"

# Insert the Feature (Lagos to Algiers straight line)
# Coordinates: Lagos (3.3792, 6.5244), Algiers (3.0420, 36.7528)
# Geometry Blob Construction (GPKG Header + WKB):
# Header: Magic(0x47504B47) Ver(00) Flags(01 - binary, little endian, no env) SRS(E6100000 - 4326)
# WKB: Order(01) Type(02000000 - LineString) Num(02000000)
# Pt1(Lagos):  X=3.3792 (6E861BF0F0080B40) Y=6.5244 (A4703D0AD7181A40)
# Pt2(Algiers): X=3.0420 (5C8FC2F528550840) Y=36.7528 (B29DEFA7C6604240)
# Hex String:
BLOB_HEX="47504B470001E61000000102000000020000006E861BF0F0080B40A4703D0AD7181A405C8FC2F528550840B29DEFA7C6604240"

sqlite3 "$GPKG" "INSERT INTO highway_segments (geom, name, type) VALUES (x'$BLOB_HEX', 'Trans-African Hwy 2', 'Proposed');"

# 4. Launch QField
echo "Launching QField..."
# Force stop to ensure reload
am force-stop $PACKAGE
sleep 1

# Launch directly into the project view
am start -a android.intent.action.VIEW \
    -d "file://$GPKG" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity"

# Wait for load
sleep 10

# Dismiss potential dialogs (Tutorials/Release notes)
# Tap "Skip" or "Close" coordinates based on common screen sizes (simulated)
input tap 991 357 2>/dev/null || true # Skip tutorial X
sleep 1

echo "=== Setup complete ==="