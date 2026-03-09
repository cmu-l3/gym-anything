#!/bin/bash
set -e
echo "=== Setting up explode_multipart_geometries task ==="

source /workspace/scripts/task_utils.sh

# 1. Install verification dependencies (gdal-bin for ogrinfo)
# We need this to verify the shapefile content in export_result.sh
if ! command -v ogrinfo &> /dev/null; then
    echo "Installing gdal-bin for verification..."
    apt-get update -qq && apt-get install -y -qq gdal-bin
fi

# 2. Prepare directories and permissions
EXPORT_DIR="/home/ga/gvsig_data/exports"
mkdir -p "$EXPORT_DIR"
chown -R ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"

# 3. Clean up previous results
OUTPUT_FILE="$EXPORT_DIR/countries_singlepart.shp"
rm -f "$EXPORT_DIR/countries_singlepart."*
echo "Cleaned previous output: $OUTPUT_FILE"

# 4. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Verify input data exists
check_countries_shapefile || exit 1

# 6. Launch gvSIG with the base project containing the countries layer
# We use the pre-built project to ensure consistent starting state
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

if [ -f "$CLEAN_PROJECT" ]; then
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

if [ -f "$PREBUILT_PROJECT" ]; then
    echo "Launching gvSIG with project: $PREBUILT_PROJECT"
    launch_gvsig "$PREBUILT_PROJECT"
else
    echo "WARNING: Pre-built project not found, launching empty gvSIG..."
    launch_gvsig ""
fi

# 7. Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="