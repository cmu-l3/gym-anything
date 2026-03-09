#!/bin/bash
echo "=== Setting up create_formatted_label_field task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define paths
DATA_DIR="/home/ga/gvsig_data/countries"
SHP_BASE="ne_110m_admin_0_countries"
BACKUP_DIR="/home/ga/gvsig_data_backup/countries"

# Ensure backup exists and restore from it to guarantee clean state
# The environment installation downloads data to DATA_DIR.
# We'll create a backup if it doesn't exist, or restore if it does.
if [ ! -d "$BACKUP_DIR" ]; then
    echo "Creating data backup..."
    mkdir -p "$BACKUP_DIR"
    cp "$DATA_DIR/$SHP_BASE".* "$BACKUP_DIR/" 2>/dev/null || true
else
    echo "Restoring data from backup to ensure clean state..."
    cp "$BACKUP_DIR/$SHP_BASE".* "$DATA_DIR/" 2>/dev/null || true
fi

# Ensure write permissions
chown -R ga:ga "/home/ga/gvsig_data"
chmod -R 755 "/home/ga/gvsig_data"

# Kill any running gvSIG instances
kill_gvsig

# Use the pre-built project which has the layer loaded
PROJECT_FILE="/home/ga/gvsig_data/projects/countries_base.gvsproj"
PREBUILT_SOURCE="/workspace/data/projects/countries_base.gvsproj"

# Restore project file if available
if [ -f "$PREBUILT_SOURCE" ]; then
    mkdir -p "$(dirname "$PROJECT_FILE")"
    cp "$PREBUILT_SOURCE" "$PROJECT_FILE"
    chown ga:ga "$PROJECT_FILE"
fi

# Launch gvSIG
echo "Launching gvSIG with project..."
launch_gvsig "$PROJECT_FILE"

# Record initial file timestamp of the DBF (to check for modification later)
DBF_FILE="$DATA_DIR/$SHP_BASE.dbf"
if [ -f "$DBF_FILE" ]; then
    stat -c %Y "$DBF_FILE" > /tmp/initial_dbf_mtime.txt
else
    echo "0" > /tmp/initial_dbf_mtime.txt
fi

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="