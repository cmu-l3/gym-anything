#!/bin/bash
echo "=== Setting up merge_country_features task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 2. Ensure clean state
# Kill gvSIG if running to ensure fresh start
kill_gvsig

# Clean exports directory
EXPORTS_DIR="/home/ga/gvsig_data/exports"
rm -rf "$EXPORTS_DIR"
mkdir -p "$EXPORTS_DIR"
chown ga:ga "$EXPORTS_DIR"

# 3. Restore clean project file
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

if [ -f "$CLEAN_PROJECT" ]; then
    echo "Restoring clean project..."
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

# 4. Launch gvSIG with the project
if [ -f "$PREBUILT_PROJECT" ]; then
    echo "Launching gvSIG with countries_base project..."
    launch_gvsig "$PREBUILT_PROJECT"
else
    echo "WARNING: Project file not found, launching empty gvSIG..."
    launch_gvsig ""
fi

# 5. Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="