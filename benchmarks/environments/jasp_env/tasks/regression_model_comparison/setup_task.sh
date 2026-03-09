#!/bin/bash
echo "=== Setting up regression_model_comparison task ==="

# Kill any running JASP instance
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 3

# ============================================================
# Ensure the World Happiness dataset exists
# The install script does not download this dataset, so we
# fetch it from the JASP Data Library bundled with the flatpak
# or download from the official JASP GitHub repository.
# ============================================================
DATASET="/home/ga/Documents/JASP/WorldHappiness.csv"
mkdir -p /home/ga/Documents/JASP

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

    # Also check /opt/jasp_datasets as a fallback source
    if [ ! -f "$DATASET" ] || [ "$(stat -c%s "$DATASET" 2>/dev/null || echo 0)" -lt 100 ]; then
        if [ -f "/opt/jasp_datasets/World Happiness.csv" ]; then
            cp "/opt/jasp_datasets/World Happiness.csv" "$DATASET"
        fi
    fi

    chown ga:ga "$DATASET"
fi

# Validate the dataset
DATASET_SIZE=$(stat -c%s "$DATASET" 2>/dev/null || echo 0)
if [ "$DATASET_SIZE" -lt 100 ]; then
    echo "ERROR: WorldHappiness.csv is missing or too small (${DATASET_SIZE} bytes)"
    exit 1
fi
echo "Dataset ready: $DATASET (${DATASET_SIZE} bytes)"
head -3 "$DATASET"

# ============================================================
# Record baseline state
# ============================================================
echo "$(date +%s)" > /tmp/regression_model_comparison_start_time
echo "Baseline timestamp recorded."

# ============================================================
# Launch JASP with the dataset pre-loaded
# Uses setsid so the process survives when su exits.
# ============================================================
su - ga -c "setsid /usr/local/bin/launch-jasp $DATASET > /tmp/jasp_task.log 2>&1 &"
sleep 22

# Dismiss any startup dialogs
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 2

# Maximize the JASP window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

echo "=== regression_model_comparison task setup complete ==="
