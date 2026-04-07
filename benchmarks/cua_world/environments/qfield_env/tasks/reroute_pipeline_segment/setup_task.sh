#!/system/bin/sh
# Setup script for reroute_pipeline_segment task
# Runs inside Android emulator

echo "=== Setting up Reroute Pipeline Task ==="

PACKAGE="ch.opengis.qfield"
GPKG_SRC="/sdcard/QFieldData/world_survey.gpkg"
GPKG_DEST="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
TASK_DIR="/sdcard/tasks/reroute_pipeline_segment"

# 1. Record Start Time
date +%s > "$TASK_DIR/start_time.txt"

# 2. Clean up and Prepare GeoPackage
# We need a fresh writable copy
echo "Preparing GeoPackage..."
mkdir -p /sdcard/Android/data/ch.opengis.qfield/files
cp "$GPKG_SRC" "$GPKG_DEST"
chmod 666 "$GPKG_DEST"

# 3. Inject 'pipelines' table and initial data via sqlite3
# Note: GeoPackage uses a standard SQLite structure.
# We create a table and register it in gpkg_contents and gpkg_geometry_columns.
# Initial Geometry: LineString(30.04 31.23, 44.36 33.31) -> Cairo to Baghdad
# WKB (Little Endian):
# 01 (ByteOrder) 02000000 (Type=LineString) 02000000 (NumPoints=2)
# Point 1 (30.04, 31.23): 7B14AE47E10A3E40 1F85EB51B83A3F40
# Point 2 (44.36, 33.31): A4703D0AD72E4640 EC51B81E85AA4040
#
# GPKG Blob Header:
# Magic: 47 50 ('GP')
# Version: 00
# Flags: 01 (Binary 00000001 -> Little Endian, SRS ID present)
# SRS ID: E6 10 00 00 (4326)
# Envelope: None (Flags say so? No, actually let's use standard GPKG blob)
# For simplicity, we can insert WKB directly if the viewer supports it, 
# but QField expects proper GPKG blobs.
#
# Let's use a simpler approach: The world_survey.gpkg might already have SpatiaLite support if we use standard tools.
# But `sqlite3` on Android is barebones.
# We will use a pre-calculated hex blob for the initial straight line.

# Header (8 bytes: GP, Ver, Flags, SRS) + WKB
# Flags 0 (Empty) -> No envelope. 
# Blob: 47500000 E6100000 (SRS 4326) + WKB
# WKB: 01 02000000 02000000 7B14AE47E10A3E40 1F85EB51B83A3F40 A4703D0AD72E4640 EC51B81E85AA4040
HEX_BLOB="47500000E61000000102000000020000007B14AE47E10A3E401F85EB51B83A3F40A4703D0AD72E4640EC51B81E85AA4040"

echo "Injecting pipeline data..."
sqlite3 "$GPKG_DEST" <<EOF
-- Create table
CREATE TABLE pipelines (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT,
    status TEXT,
    geom BLOB
);

-- Register table
INSERT INTO gpkg_contents (table_name, data_type, identifier, description, last_change, srs_id) 
VALUES ('pipelines', 'features', 'pipelines', 'Pipeline Routes', strftime('%Y-%m-%dT%H:%M:%fZ','now'), 4326);

-- Register geometry column
INSERT INTO gpkg_geometry_columns (table_name, column_name, geometry_type_name, srs_id, z, m) 
VALUES ('pipelines', 'geom', 'LINESTRING', 4326, 0, 0);

-- Insert feature
INSERT INTO pipelines (name, status, geom) 
VALUES ('Cairo-Baghdad', 'Planned', x'$HEX_BLOB');
EOF

# 4. Force stop QField to ensure it reloads the file
am force-stop $PACKAGE
sleep 2

# 5. Launch QField
# We use VIEW intent to open the project directly
echo "Launching QField..."
am start -a android.intent.action.VIEW \
    -d "file://$GPKG_DEST" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null

# Wait for load
sleep 10

# 6. Take initial screenshot
screencap -p "$TASK_DIR/initial_state.png"

echo "=== Setup Complete ==="