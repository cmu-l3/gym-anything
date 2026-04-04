#!/bin/bash
set -e
echo "=== Setting up create_point_shapefile task ==="

source /workspace/scripts/task_utils.sh

# 1. Install verification dependencies (pyshp)
# We do this here to ensure export_result.sh can parse the shapefile later
if ! python3 -c "import shapefile" 2>/dev/null; then
    echo "Installing pyshp for verification..."
    pip3 install --no-cache-dir pyshp 2>/dev/null || echo "WARNING: pip install failed, verification might be limited"
fi

# 2. Prepare directories
EXPORTS_DIR="/home/ga/gvsig_data/exports"
mkdir -p "$EXPORTS_DIR"
# Clean up any previous attempts to ensure "Created During Task" check works
rm -f "$EXPORTS_DIR"/survey_sites.* 2>/dev/null || true
chown -R ga:ga "/home/ga/gvsig_data"

# 3. Record task start time and initial state
date +%s > /tmp/task_start_time.txt
ls -la "$EXPORTS_DIR" > /tmp/initial_dir_listing.txt

# 4. Launch gvSIG with the base project
# Using the pre-built countries project gives context
PROJECT_FILE="/home/ga/gvsig_data/projects/countries_base.gvsproj"

# Ensure the project exists (copy from workspace data if needed)
if [ ! -f "$PROJECT_FILE" ] && [ -f "/workspace/data/projects/countries_base.gvsproj" ]; then
    cp "/workspace/data/projects/countries_base.gvsproj" "$PROJECT_FILE"
    chown ga:ga "$PROJECT_FILE"
fi

echo "Launching gvSIG..."
kill_gvsig
launch_gvsig "$PROJECT_FILE"

# 5. Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="