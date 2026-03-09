#!/bin/bash
echo "=== Setting up identify_equatorial_countries task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure data directories exist and are writable
mkdir -p /home/ga/gvsig_data/exports
chown -R ga:ga /home/ga/gvsig_data

# Remove previous output if it exists
rm -f /home/ga/gvsig_data/exports/equatorial_countries.*

# Install pyshp for the export script to use later (for content verification)
# We do this in setup to ensure the tool is available when export runs
echo "Installing verification dependencies..."
pip3 install pyshp > /dev/null 2>&1 || true

# Kill any running gvSIG instances
kill_gvsig

# Restore clean project state
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

if [ -f "$CLEAN_PROJECT" ]; then
    echo "Restoring clean project..."
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

# Launch gvSIG with the base project
if [ -f "$PREBUILT_PROJECT" ]; then
    echo "Launching gvSIG with project: $PREBUILT_PROJECT"
    launch_gvsig "$PREBUILT_PROJECT"
else
    echo "WARNING: Prebuilt project not found, launching empty gvSIG"
    launch_gvsig ""
fi

# Take initial screenshot
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="