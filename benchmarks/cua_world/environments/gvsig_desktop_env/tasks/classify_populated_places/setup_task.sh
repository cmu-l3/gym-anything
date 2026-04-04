#!/bin/bash
echo "=== Setting up classify_populated_places task ==="

source /workspace/scripts/task_utils.sh

# Install pyshp for verification (using sudo)
echo "Installing verification dependencies..."
sudo pip3 install pyshp > /dev/null 2>&1 || true

# Define paths
DATA_DIR="/home/ga/gvsig_data/cities"
ORIGINAL_SHP="$DATA_DIR/ne_110m_populated_places.shp"
BACKUP_SHP="$DATA_DIR/ne_110m_populated_places_backup.shp"

# Ensure clean state: Restore from backup if exists, or create backup
if [ -f "$BACKUP_SHP" ]; then
    echo "Restoring clean shapefile..."
    cp "$BACKUP_SHP" "$ORIGINAL_SHP"
    cp "${BACKUP_SHP%.shp}.shx" "${ORIGINAL_SHP%.shp}.shx"
    cp "${BACKUP_SHP%.shp}.dbf" "${ORIGINAL_SHP%.shp}.dbf"
    cp "${BACKUP_SHP%.shp}.prj" "${ORIGINAL_SHP%.shp}.prj" 2>/dev/null || true
else
    echo "Creating backup of original shapefile..."
    cp "$ORIGINAL_SHP" "$BACKUP_SHP"
    cp "${ORIGINAL_SHP%.shp}.shx" "${BACKUP_SHP%.shp}.shx"
    cp "${ORIGINAL_SHP%.shp}.dbf" "${BACKUP_SHP%.shp}.dbf"
    cp "${ORIGINAL_SHP%.shp}.prj" "${BACKUP_SHP%.shp}.prj" 2>/dev/null || true
fi

# Set permissions
chown -R ga:ga "$DATA_DIR"
chmod 755 "$DATA_DIR"
chmod 644 "$DATA_DIR"/*

# Record start time and initial file timestamp
date +%s > /tmp/task_start_time.txt
stat -c %Y "$ORIGINAL_SHP" > /tmp/initial_shp_mtime.txt
echo "Task start time recorded."

# Kill any running gvSIG
kill_gvsig

# Launch gvSIG with a fresh/empty view
echo "Launching gvSIG..."
launch_gvsig ""

# Note: We rely on the agent to load the layer as part of the task (Step 1),
# because xdotool loading is flaky and we want to test their ability to find the file.
# The description has been updated to include "Load Data" as step 1.

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="