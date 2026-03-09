#!/bin/bash
echo "=== Setting up identify_cities_near_borders task ==="

source /workspace/scripts/task_utils.sh

# Install pyshp for the export/verification script later
# (doing it here to avoid taking time during export)
if ! python3 -c "import shapefile" 2>/dev/null; then
    echo "Installing pyshp for verification..."
    pip3 install pyshp > /dev/null 2>&1 || true
fi

# Ensure data directories exist and are writable
mkdir -p /home/ga/gvsig_data/exports
# Clean up previous output
rm -f /home/ga/gvsig_data/exports/border_cities.* 2>/dev/null

# Ensure input data exists
check_countries_shapefile || exit 1
if [ ! -f "/home/ga/gvsig_data/cities/ne_110m_populated_places.shp" ]; then
    echo "ERROR: Cities shapefile not found!"
    exit 1
fi

# Set permissions
chown -R ga:ga /home/ga/gvsig_data

# Kill any running gvSIG
kill_gvsig

# Use the pre-built project which has countries loaded
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

# Restore clean project state
if [ -f "$CLEAN_PROJECT" ]; then
    echo "Restoring clean project..."
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Launch gvSIG
if [ -f "$PREBUILT_PROJECT" ]; then
    echo "Launching gvSIG with countries project..."
    launch_gvsig "$PREBUILT_PROJECT"
else
    echo "Launching gvSIG empty..."
    launch_gvsig ""
fi

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved."

echo "=== Task setup complete ==="