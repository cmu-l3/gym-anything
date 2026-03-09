#!/bin/bash
echo "=== Setting up edit_attribute_values task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure data directories exist and are writable
mkdir -p /home/ga/gvsig_data/projects
chown -R ga:ga /home/ga/gvsig_data

# Data path
DBF_PATH="/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.dbf"

# 1. Kill any running gvSIG instances
kill_gvsig

# 2. Reset the data to a clean state
# We need to ensure the DBF has the original values, not modified ones from previous runs
echo "Restoring clean shapefile data..."
if [ -f "/workspace/data/countries/ne_110m_admin_0_countries.dbf" ]; then
    # If we have a backup in workspace
    cp "/workspace/data/countries/ne_110m_admin_0_countries.dbf" "$DBF_PATH"
    cp "/workspace/data/countries/ne_110m_admin_0_countries.shp" "${DBF_PATH%.dbf}.shp"
    cp "/workspace/data/countries/ne_110m_admin_0_countries.shx" "${DBF_PATH%.dbf}.shx"
    # Also restore .prj if exists
    [ -f "/workspace/data/countries/ne_110m_admin_0_countries.prj" ] && cp "/workspace/data/countries/ne_110m_admin_0_countries.prj" "${DBF_PATH%.dbf}.prj"
else
    # Fallback: re-download or unzip if workspace backup is missing (unlikely if env is built right)
    # For now, we assume the env install script put data in /home/ga/gvsig_data and we just touch it to update timestamp
    # Realistically, in a persistent env, we'd unzip a fresh copy here.
    # Let's try to unzip from the original download if available, or just proceed.
    echo "Warning: No clean backup found in /workspace/data. Using current state."
fi

# Ensure permissions
chown ga:ga "$DBF_PATH"
chmod 644 "$DBF_PATH"

# Record initial file timestamp
stat -c %Y "$DBF_PATH" > /tmp/initial_dbf_mtime.txt
echo "Initial DBF mtime: $(cat /tmp/initial_dbf_mtime.txt)"

# 3. Setup Project File
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

if [ -f "$CLEAN_PROJECT" ]; then
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

# 4. Launch gvSIG
if [ -f "$PREBUILT_PROJECT" ]; then
    echo "Launching gvSIG with project: $PREBUILT_PROJECT"
    launch_gvsig "$PREBUILT_PROJECT"
else
    echo "Launching fresh gvSIG (project not found)..."
    launch_gvsig ""
fi

# 5. Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved."

echo "=== Task setup complete ==="