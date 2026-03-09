#!/bin/bash
set -e
echo "=== Setting up clip_rivers_to_country task ==="

source /workspace/scripts/task_utils.sh

# 1. Install verification dependencies (gdal-bin for ogrinfo)
# We do this in setup to ensure export_result.sh has the tools it needs
if ! command -v ogrinfo &> /dev/null; then
    echo "Installing gdal-bin for verification..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -y -qq gdal-bin > /dev/null
fi

# 2. Prepare Data Directories
DATA_DIR="/home/ga/gvsig_data"
EXPORTS_DIR="$DATA_DIR/exports"
PROJECTS_DIR="$DATA_DIR/projects"

# Ensure clean state
rm -rf "$EXPORTS_DIR"
mkdir -p "$EXPORTS_DIR"
chown -R ga:ga "$DATA_DIR"

# 3. Verify Input Data Exists
RIVERS_SHP="$DATA_DIR/rivers/ne_110m_rivers_lake_centerlines.shp"
COUNTRIES_SHP="$DATA_DIR/countries/ne_110m_admin_0_countries.shp"

if [ ! -f "$RIVERS_SHP" ] || [ ! -f "$COUNTRIES_SHP" ]; then
    echo "ERROR: Required shapefiles not found!"
    ls -R "$DATA_DIR"
    exit 1
fi

# 4. Record Initial State & Timestamp
date +%s > /tmp/task_start_time.txt
echo "Task started at $(cat /tmp/task_start_time.txt)"

# 5. Launch gvSIG with Base Project
# We use the countries_base project which has the countries layer pre-loaded.
# The agent will need to load the rivers layer themselves.
PROJECT_FILE="$PROJECTS_DIR/countries_base.gvsproj"
PREBUILT_SOURCE="/workspace/data/projects/countries_base.gvsproj"

# Reset project file
if [ -f "$PREBUILT_SOURCE" ]; then
    cp "$PREBUILT_SOURCE" "$PROJECT_FILE"
    chown ga:ga "$PROJECT_FILE"
fi

echo "Launching gvSIG with project: $PROJECT_FILE"
launch_gvsig "$PROJECT_FILE"

# 6. Final Setup
sleep 5
# Take initial screenshot
take_screenshot /tmp/task_initial.png

# Ensure window is maximized
DISPLAY=:1 wmctrl -r "gvSIG" -b add,maximized_vert,maximized_horz 2>/dev/null || true

echo "=== Task setup complete ==="