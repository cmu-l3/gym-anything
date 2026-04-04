#!/bin/bash
set -e
echo "=== Setting up configure_layer_filter task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure data directories exist
mkdir -p /home/ga/gvsig_data/projects
chown -R ga:ga /home/ga/gvsig_data

# 1. Clean up target file
TARGET_PROJECT="/home/ga/gvsig_data/projects/sa_regional.gvsproj"
rm -f "$TARGET_PROJECT"
echo "Removed previous target file: $TARGET_PROJECT"

# 2. Prepare the starting project
# We use a pre-built project that has the countries layer already loaded
# to save the agent from doing the loading step.
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

# Restore from read-only workspace if available to ensure clean state
if [ -f "$CLEAN_PROJECT" ]; then
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
    echo "Restored starting project: $PREBUILT_PROJECT"
fi

# 3. Launch gvSIG
kill_gvsig
if [ -f "$PREBUILT_PROJECT" ]; then
    launch_gvsig "$PREBUILT_PROJECT"
else
    # Fallback if project missing (shouldn't happen in valid env)
    echo "WARNING: Starting project not found, launching empty gvSIG"
    launch_gvsig ""
fi

# 4. Initial state evidence
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="