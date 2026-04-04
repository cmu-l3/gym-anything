#!/bin/bash
echo "=== Setting up graduated_color_choropleth task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Clean up any previous run artifacts
OUTPUT_FILE="/home/ga/gvsig_data/projects/population_choropleth.gvsproj"
rm -f "$OUTPUT_FILE" 2>/dev/null || true

# Ensure data directory permissions
chown -R ga:ga /home/ga/gvsig_data

# Verify required data exists
if ! check_countries_shapefile; then
    echo "ERROR: Countries shapefile missing!"
    exit 1
fi

# Kill any existing instances
kill_gvsig

# Copy base project (countries_base.gvsproj) to ensure clean state
# This project has the countries layer already loaded
PROJECTS_DIR="/home/ga/gvsig_data/projects"
mkdir -p "$PROJECTS_DIR"
BASE_PROJECT_SOURCE="/workspace/data/projects/countries_base.gvsproj"
BASE_PROJECT_DEST="$PROJECTS_DIR/countries_base.gvsproj"

if [ -f "$BASE_PROJECT_SOURCE" ]; then
    cp "$BASE_PROJECT_SOURCE" "$BASE_PROJECT_DEST"
    chown ga:ga "$BASE_PROJECT_DEST"
    chmod 644 "$BASE_PROJECT_DEST"
    echo "Restored base project: $BASE_PROJECT_DEST"
fi

# Launch gvSIG with the base project
echo "Launching gvSIG with countries_base.gvsproj..."
launch_gvsig "$BASE_PROJECT_DEST"

# Allow time for UI to stabilize
sleep 5

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured: /tmp/task_initial.png"

echo "=== Task setup complete ==="