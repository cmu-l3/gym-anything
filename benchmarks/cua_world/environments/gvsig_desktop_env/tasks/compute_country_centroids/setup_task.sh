#!/bin/bash
echo "=== Setting up compute_country_centroids task ==="

source /workspace/scripts/task_utils.sh

# 1. Install pyshp for verification (runs in container)
echo "Installing pyshp for verification..."
pip3 install pyshp > /dev/null 2>&1 || true

# 2. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Clean up previous artifacts
EXPORT_DIR="/home/ga/gvsig_data/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/country_centroids."*
chown -R ga:ga "$EXPORT_DIR"

# 4. Prepare gvSIG state
# We use the pre-built project which has the countries layer already loaded
# This ensures a consistent starting state (View open, layer present)
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

# Restore clean project to prevent state pollution
if [ -f "$CLEAN_PROJECT" ]; then
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

# 5. Launch gvSIG
kill_gvsig
echo "Launching gvSIG with countries project..."
if [ -f "$PREBUILT_PROJECT" ]; then
    launch_gvsig "$PREBUILT_PROJECT"
else
    # Fallback if project missing: launch empty and user must load layer
    # (Task description assumes layer is loaded, so this is a fallback)
    launch_gvsig ""
fi

# 6. Capture initial state
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="