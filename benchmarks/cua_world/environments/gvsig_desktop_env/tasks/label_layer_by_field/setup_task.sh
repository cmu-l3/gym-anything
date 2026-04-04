#!/bin/bash
echo "=== Setting up label_layer_by_field task ==="

source /workspace/scripts/task_utils.sh

# Verify data exists
check_countries_shapefile || exit 1
SHP_PATH=$(ls /home/ga/gvsig_data/countries/*.shp 2>/dev/null | head -1)
echo "Countries shapefile: $SHP_PATH"

# Ensure data dir is writable
chown -R ga:ga /home/ga/gvsig_data

# Kill any running gvSIG
kill_gvsig

# Re-copy the clean pre-built project on every task start to prevent state bleed
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

if [ -f "$CLEAN_PROJECT" ]; then
    echo "Restoring clean project from workspace: $CLEAN_PROJECT"
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

if [ -f "$PREBUILT_PROJECT" ]; then
    echo "Using pre-built project: $PREBUILT_PROJECT"
    launch_gvsig "$PREBUILT_PROJECT"
else
    echo "Launching fresh gvSIG..."
    launch_gvsig ""
fi

# Take initial screenshot
sleep 3
take_screenshot /tmp/task_start.png
echo "Initial screenshot saved to /tmp/task_start.png"

echo "=== Task setup complete ==="
echo "Task: Enable country name labels (NAME field) on the countries layer"
