#!/bin/bash
echo "=== Setting up simplify_country_geometries task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Directories
DATA_DIR="/home/ga/gvsig_data"
EXPORT_DIR="$DATA_DIR/exports"
COUNTRIES_SHP="$DATA_DIR/countries/ne_110m_admin_0_countries.shp"

# Ensure data exists
if [ ! -f "$COUNTRIES_SHP" ]; then
    echo "ERROR: Input shapefile not found at $COUNTRIES_SHP"
    exit 1
fi

# Prepare export directory (clean previous runs)
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/countries_simplified."*
chown -R ga:ga "$DATA_DIR"
chmod -R 755 "$DATA_DIR"

# Kill any existing gvSIG instances
kill_gvsig

# Launch gvSIG with the pre-built project (countries layer loaded)
# Using the pre-built project ensures the layer is already in the ToC
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
    echo "WARNING: Pre-built project not found, launching fresh gvSIG..."
    launch_gvsig ""
fi

# Take initial screenshot of the starting state
sleep 5
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="
echo "Task: Simplify $COUNTRIES_SHP"
echo "Target: Tolerance 0.5 -> $EXPORT_DIR/countries_simplified.shp"