#!/bin/bash
echo "=== Setting up generate_country_bounding_boxes task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 1. Prepare Data
# Verify input data exists
check_countries_shapefile || exit 1

# Ensure export directory exists and is empty
EXPORT_DIR="/home/ga/gvsig_data/exports"
rm -rf "$EXPORT_DIR" 2>/dev/null || true
mkdir -p "$EXPORT_DIR"
chown -R ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"

# 2. Setup gvSIG
# Kill any running gvSIG instances
kill_gvsig

# Restore clean project state to ensure "ne_110m_admin_0_countries" is loaded
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

mkdir -p "$(dirname "$PREBUILT_PROJECT")"
if [ -f "$CLEAN_PROJECT" ]; then
    echo "Restoring clean project: $CLEAN_PROJECT"
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

# Launch gvSIG with the project
if [ -f "$PREBUILT_PROJECT" ]; then
    echo "Launching gvSIG with project..."
    launch_gvsig "$PREBUILT_PROJECT"
else
    echo "WARNING: Pre-built project not found, launching empty..."
    launch_gvsig ""
fi

# 3. Final Prep
# Ensure window is maximized and focused
WID=$(DISPLAY=:1 wmctrl -l | grep -i "gvSIG" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
    DISPLAY=:1 wmctrl -i -a "$WID"
fi

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="