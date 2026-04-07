#!/system/bin/sh
set -e
echo "=== Setting up identify_meridian_capital task ==="

# Define paths
TASK_DIR="/sdcard/tasks/identify_meridian_capital"
DATA_DIR="/sdcard/Android/data/ch.opengis.qfield/files"
GPKG_SRC="/sdcard/QFieldData/world_survey.gpkg"
GPKG_DST="$DATA_DIR/Imported Datasets/world_survey.gpkg"

# Ensure task directory exists
mkdir -p "$TASK_DIR"

# 1. Prepare Data
# We copy the GeoPackage to the app's data directory to ensure it's visible and writable
echo "Preparing GeoPackage..."
mkdir -p "$DATA_DIR/Imported Datasets"
cp "$GPKG_SRC" "$GPKG_DST"
chmod 666 "$GPKG_DST"

# 2. Calculate Ground Truth (Hidden from agent)
# We use sqlite3 to find the capital closest to 25.0
echo "Calculating ground truth..."
GT_QUERY="SELECT name, longitude, ABS(longitude - 25.0) as diff FROM world_capitals ORDER BY diff LIMIT 1;"
GT_RESULT=$(sqlite3 "$GPKG_DST" "$GT_QUERY")
echo "$GT_RESULT" > "$TASK_DIR/ground_truth.txt"
# Format: CityName|Longitude|Diff
echo "Ground Truth Calculated: $GT_RESULT"

# 3. Record Initial State
# Count observations to detect if agent actually adds one
INITIAL_COUNT=$(sqlite3 "$GPKG_DST" "SELECT COUNT(*) FROM field_observations;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > "$TASK_DIR/initial_count.txt"
date +%s > "$TASK_DIR/start_time.txt"

# 4. App Setup
# Force stop QField to ensure clean start
echo "Stopping QField..."
am force-stop ch.opengis.qfield
sleep 2

# Launch QField directly to the project
# Note: Using VIEW intent with correct mime type for GeoPackage
echo "Launching QField..."
am start -a android.intent.action.VIEW \
    -d "file://$GPKG_DST" \
    -t "application/geopackage+sqlite3" \
    -n "ch.opengis.qfield/.QFieldActivity"

# Wait for app to load
sleep 10

echo "=== Task setup complete ==="