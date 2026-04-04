#!/bin/bash
echo "=== Setting up create_map_layout task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare Data
# Verify countries shapefile exists
check_countries_shapefile || exit 1

# Ensure export directory exists and is clean
EXPORT_DIR="/home/ga/gvsig_data/exports"
mkdir -p "$EXPORT_DIR"
# Remove any previous output to ensure new creation
rm -f "$EXPORT_DIR/world_map_layout.png"
chown -R ga:ga "$EXPORT_DIR"

# 2. Record Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Setup Project
# We use the prebuilt project 'countries_base.gvsproj' which has the View and Layer loaded.
# This saves the agent from having to load data, focusing the task on the Layout creation.
PROJECT_DIR="/home/ga/gvsig_data/projects"
mkdir -p "$PROJECT_DIR"
PREBUILT_PROJECT="$PROJECT_DIR/countries_base.gvsproj"
SOURCE_PROJECT="/workspace/data/projects/countries_base.gvsproj"

# Always restore a clean copy of the project
if [ -f "$SOURCE_PROJECT" ]; then
    echo "Restoring clean project..."
    cp "$SOURCE_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
else
    echo "WARNING: Prebuilt project not found in workspace data!"
fi

# 4. Launch Application
# Kill any existing instances
kill_gvsig

# Launch gvSIG with the project
echo "Launching gvSIG with project: $PREBUILT_PROJECT"
launch_gvsig "$PREBUILT_PROJECT"

# 5. Initial Evidence
sleep 5
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="