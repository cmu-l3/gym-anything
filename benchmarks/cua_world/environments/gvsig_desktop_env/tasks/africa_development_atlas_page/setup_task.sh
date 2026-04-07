#!/bin/bash
echo "=== Setting up Africa Development Atlas Page task ==="

source /workspace/scripts/task_utils.sh

# Install tools needed by export_result.sh (if not present)
if ! command -v identify &> /dev/null; then
    echo "Installing imagemagick for image analysis..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -y -qq imagemagick > /dev/null 2>&1
fi

# Ensure pip and pyshp are available for DBF analysis in export
pip3 install pyshp > /dev/null 2>&1 || true

# ----------------------------------------------------------------
# 1. Verify source data
# ----------------------------------------------------------------
echo "Verifying source data..."
check_countries_shapefile || exit 1

CITIES_SHP="/home/ga/gvsig_data/cities/ne_110m_populated_places.shp"
if [ ! -f "$CITIES_SHP" ]; then
    echo "ERROR: Cities shapefile not found at $CITIES_SHP"
    exit 1
fi

# ----------------------------------------------------------------
# 2. Ensure directories exist and are writable
# ----------------------------------------------------------------
mkdir -p /home/ga/gvsig_data/exports
chown -R ga:ga /home/ga/gvsig_data

# ----------------------------------------------------------------
# 3. Clean previous output artifacts (BEFORE recording timestamp)
# ----------------------------------------------------------------
rm -f /home/ga/gvsig_data/exports/africa_dev_index.* 2>/dev/null

# ----------------------------------------------------------------
# 4. Record task start time (anti-gaming)
# ----------------------------------------------------------------
date +%s > /tmp/task_start_time.txt

# ----------------------------------------------------------------
# 5. Back up countries DBF for verifier comparison
# ----------------------------------------------------------------
DBF_PATH="/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.dbf"
if [ -f "$DBF_PATH" ]; then
    cp "$DBF_PATH" "${DBF_PATH}.bak"
fi

# ----------------------------------------------------------------
# 6. Restore clean project
# ----------------------------------------------------------------
PROJECT_DIR="/home/ga/gvsig_data/projects"
mkdir -p "$PROJECT_DIR"

PREBUILT_PROJECT="$PROJECT_DIR/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

if [ -f "$CLEAN_PROJECT" ]; then
    echo "Restoring clean project from workspace..."
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
else
    echo "WARNING: Clean project not found at $CLEAN_PROJECT"
fi

# ----------------------------------------------------------------
# 7. Launch gvSIG with the base project
# ----------------------------------------------------------------
kill_gvsig

if [ -f "$PREBUILT_PROJECT" ]; then
    echo "Launching gvSIG with base project..."
    launch_gvsig "$PREBUILT_PROJECT"
else
    echo "No base project available, launching empty..."
    launch_gvsig ""
fi

# ----------------------------------------------------------------
# 8. Initial screenshot
# ----------------------------------------------------------------
sleep 5
take_screenshot /tmp/task_start.png
echo "Initial screenshot saved to /tmp/task_start.png"

echo "=== Task setup complete ==="
