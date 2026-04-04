#!/bin/bash
echo "=== Setting up save_project_to_file task ==="

source /workspace/scripts/task_utils.sh

# Verify data exists
check_countries_shapefile || exit 1
SHP_PATH=$(ls /home/ga/gvsig_data/countries/*.shp 2>/dev/null | head -1)

# Clean up any existing project with the expected name so agent must create it
TARGET_PROJECT="/home/ga/gvsig_data/projects/world_countries.gvsproj"
rm -f "$TARGET_PROJECT" 2>/dev/null || true
mkdir -p /home/ga/gvsig_data/projects
chown -R ga:ga /home/ga/gvsig_data

echo "Removed any existing target file: $TARGET_PROJECT"

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
    echo "Using pre-built project with layer loaded: $PREBUILT_PROJECT"
    launch_gvsig "$PREBUILT_PROJECT"
else
    echo "Launching fresh gvSIG..."
    launch_gvsig ""
fi

# Take initial screenshot
sleep 3
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Save gvSIG project to $TARGET_PROJECT"
