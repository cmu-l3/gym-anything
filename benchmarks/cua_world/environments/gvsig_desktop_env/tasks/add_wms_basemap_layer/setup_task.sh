#!/bin/bash
echo "=== Setting up add_wms_basemap_layer task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (critical for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
OUTPUT_PROJECT="/home/ga/gvsig_data/projects/wms_basemap_project.gvsproj"
rm -f "$OUTPUT_PROJECT" 2>/dev/null || true

# Ensure data directories exist and are writable
mkdir -p /home/ga/gvsig_data/projects
chown -R ga:ga /home/ga/gvsig_data

# Kill any stale gvSIG instances
kill_gvsig

# -------------------------------------------------------------------
# Prepare the Initial State
# We need the countries layer loaded. We use the pre-built 'countries_base.gvsproj'.
# -------------------------------------------------------------------
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

# Reset the base project to a clean state
if [ -f "$CLEAN_PROJECT" ]; then
    echo "Restoring clean base project..."
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

# Launch gvSIG with the base project
if [ -f "$PREBUILT_PROJECT" ]; then
    echo "Launching gvSIG with countries base project..."
    launch_gvsig "$PREBUILT_PROJECT"
else
    echo "WARNING: Base project not found. Launching empty gvSIG."
    launch_gvsig ""
fi

# -------------------------------------------------------------------
# Validation & Evidence
# -------------------------------------------------------------------

# Ensure window is maximized
sleep 2
WID=$(DISPLAY=:1 wmctrl -l | grep -i "gvSIG" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot to prove starting state
sleep 2
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="