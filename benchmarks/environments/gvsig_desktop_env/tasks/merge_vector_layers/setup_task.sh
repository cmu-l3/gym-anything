#!/bin/bash
set -e
echo "=== Setting up merge_vector_layers task ==="

# Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Install GDAL CLI tools for data preparation and verification
# (Using apt-get update cautiously to avoid network timeouts, suppress output)
if ! which ogr2ogr >/dev/null; then
    echo "Installing GDAL tools..."
    apt-get update -qq && apt-get install -y -qq gdal-bin > /dev/null 2>&1
fi

GVSIG_DATA_DIR="/home/ga/gvsig_data"
SPLIT_DIR="$GVSIG_DATA_DIR/split"
EXPORT_DIR="$GVSIG_DATA_DIR/exports"

# Clean artifacts
rm -rf "$SPLIT_DIR" "$EXPORT_DIR"
mkdir -p "$SPLIT_DIR"
mkdir -p "$EXPORT_DIR"

# Locate source data
COUNTRIES_SHP=$(ls "$GVSIG_DATA_DIR/countries/"*.shp 2>/dev/null | head -1)
if [ -z "$COUNTRIES_SHP" ]; then
    echo "ERROR: Base country data not found. Running install_gvsig download fallback..."
    # Fallback download if missing (should be handled by env, but robust tasks help)
    wget -q -O /tmp/ne_countries.zip "https://naciscdn.org/naturalearth/110m/cultural/ne_110m_admin_0_countries.zip"
    unzip -q -o /tmp/ne_countries.zip -d "$GVSIG_DATA_DIR/countries"
    COUNTRIES_SHP=$(ls "$GVSIG_DATA_DIR/countries/"*.shp 2>/dev/null | head -1)
fi

echo "Source: $COUNTRIES_SHP"

# Split data into two valid shapefiles
echo "Preparing input data..."
# 1. Eurasia
ogr2ogr -f "ESRI Shapefile" "$SPLIT_DIR/eurasia_countries.shp" "$COUNTRIES_SHP" \
    -where "CONTINENT IN ('Europe', 'Asia')"
# 2. Rest of World
ogr2ogr -f "ESRI Shapefile" "$SPLIT_DIR/rest_countries.shp" "$COUNTRIES_SHP" \
    -where "CONTINENT NOT IN ('Europe', 'Asia')"

# Calculate expected feature sum for verification
COUNT_1=$(ogrinfo -so "$SPLIT_DIR/eurasia_countries.shp" -al | grep "Feature Count" | awk '{print $3}')
COUNT_2=$(ogrinfo -so "$SPLIT_DIR/rest_countries.shp" -al | grep "Feature Count" | awk '{print $3}')
TOTAL_EXPECTED=$((COUNT_1 + COUNT_2))

echo "$TOTAL_EXPECTED" > /tmp/expected_feature_count.txt
echo "Input 1: $COUNT_1 features"
echo "Input 2: $COUNT_2 features"
echo "Target Total: $TOTAL_EXPECTED features"

# Set permissions
chown -R ga:ga "$SPLIT_DIR" "$EXPORT_DIR"

# Launch gvSIG
kill_gvsig
launch_gvsig ""

# Maximize window
sleep 5
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="