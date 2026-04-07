#!/bin/bash
echo "=== Setting up regression_pipeline_world_happiness task ==="

# 1. Kill any running JASP instance
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 3

# 2. Ensure the JASP working directory exists
mkdir -p /home/ga/Documents/JASP

# 3. Obtain the World Happiness dataset
# Strategy: flatpak Data Library → GitHub download → /opt fallback
DATASET="/home/ga/Documents/JASP/WorldHappiness.csv"

if [ ! -f "$DATASET" ]; then
    echo "Looking for World Happiness dataset..."

    # Try the flatpak bundled Data Library first
    FLATPAK_DATA_DIR=$(find /var/lib/flatpak/app/org.jaspstats.JASP -path "*/Resources/Data Sets" -type d 2>/dev/null | head -1)
    BUNDLED_CSV=""
    if [ -n "$FLATPAK_DATA_DIR" ]; then
        BUNDLED_CSV=$(find "$FLATPAK_DATA_DIR" -name "World Happiness.csv" -type f 2>/dev/null | head -1)
    fi

    if [ -n "$BUNDLED_CSV" ] && [ -f "$BUNDLED_CSV" ]; then
        echo "Found bundled dataset: $BUNDLED_CSV"
        cp "$BUNDLED_CSV" "$DATASET"
    else
        echo "Bundled dataset not found, downloading from JASP GitHub..."
        wget -q -O "$DATASET" \
            "https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/4.%20Regression/World%20Happiness.csv"
    fi

    # Fallback to /opt/jasp_datasets
    if [ ! -f "$DATASET" ] || [ "$(stat -c%s "$DATASET" 2>/dev/null || echo 0)" -lt 100 ]; then
        if [ -f "/opt/jasp_datasets/World Happiness.csv" ]; then
            echo "Using /opt/jasp_datasets fallback..."
            cp "/opt/jasp_datasets/World Happiness.csv" "$DATASET"
        fi
    fi

    chown ga:ga "$DATASET"
    chmod 644 "$DATASET"
fi

# 4. Validate the dataset
DATASET_SIZE=$(stat -c%s "$DATASET" 2>/dev/null || echo 0)
if [ "$DATASET_SIZE" -lt 100 ]; then
    echo "ERROR: WorldHappiness.csv is missing or too small (${DATASET_SIZE} bytes)"
    exit 1
fi
echo "Dataset ready: $DATASET (${DATASET_SIZE} bytes)"
head -3 "$DATASET"

# 5. Remove any previous output files to prevent false positives
rm -f "/home/ga/Documents/JASP/happiness_regression_pipeline.jasp"
rm -f "/home/ga/Documents/JASP/regression_report.txt"

# 6. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 7. Launch JASP with the dataset pre-loaded
echo "Launching JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp '$DATASET' > /tmp/jasp_launch.log 2>&1 &"

# 8. Wait for JASP window
echo "Waiting for JASP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# 9. Handle window state and dialogs
sleep 5
# Dismiss potential "Check for updates" or welcome dialogs
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 2

# Maximize the window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Ensure it is focused
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 10. Take initial screenshot for evidence
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== regression_pipeline_world_happiness setup complete ==="
