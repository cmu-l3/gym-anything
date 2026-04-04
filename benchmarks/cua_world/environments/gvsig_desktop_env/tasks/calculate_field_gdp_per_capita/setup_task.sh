#!/bin/bash
echo "=== Setting up calculate_field_gdp_per_capita task ==="

source /workspace/scripts/task_utils.sh

# Install standard tools for data handling if missing (useful for verification)
if ! dpkg -l | grep -q gdal-bin; then
    echo "Installing gdal-bin for verification tools..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -y -qq gdal-bin python3-pandas > /dev/null 2>&1 || true
fi

# Path to the data
COUNTRIES_DIR="/home/ga/gvsig_data/countries"
SHP_FILE="$COUNTRIES_DIR/ne_110m_admin_0_countries.shp"
DBF_FILE="$COUNTRIES_DIR/ne_110m_admin_0_countries.dbf"

# Verify data exists
if [ ! -f "$SHP_FILE" ]; then
    echo "ERROR: Countries shapefile not found!"
    exit 1
fi

# Ensure data is writable
chown -R ga:ga "$COUNTRIES_DIR"
chmod 644 "$COUNTRIES_DIR"/*

# Create a backup of the DBF to restore later/compare
cp "$DBF_FILE" "${DBF_FILE}.bak"
echo "Backed up DBF to ${DBF_FILE}.bak"

# Kill any running gvSIG
kill_gvsig

# Use pre-built project
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

if [ -f "$CLEAN_PROJECT" ]; then
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

if [ -f "$PREBUILT_PROJECT" ]; then
    launch_gvsig "$PREBUILT_PROJECT"
else
    launch_gvsig ""
fi

# Record task start time
date +%s > /tmp/task_start_time

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="