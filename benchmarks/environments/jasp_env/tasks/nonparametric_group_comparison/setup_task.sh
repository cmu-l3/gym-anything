#!/bin/bash
echo "=== Setting up nonparametric_group_comparison task ==="

# Kill any running JASP instance
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 3

# -----------------------------------------------------------
# Ensure the Heart Rate dataset exists
# Source: JASP Data Library -> 3. ANOVA -> Heart Rate.csv
# The JASP flatpak bundles this dataset; we copy it with a
# space-free filename to avoid quoting issues through su/setsid.
# -----------------------------------------------------------
DATASET="/home/ga/Documents/JASP/HeartRate.csv"
JASP_DATA_LIBRARY="/var/lib/flatpak/app/org.jaspstats.JASP/x86_64/stable/*/files/Resources/Data Sets/Data Library/3. ANOVA/Heart Rate.csv"

if [ ! -f "$DATASET" ]; then
    echo "Copying Heart Rate dataset..."
    mkdir -p /home/ga/Documents/JASP

    # Try the flatpak bundled data library first (glob for hash)
    SRC=$(ls $JASP_DATA_LIBRARY 2>/dev/null | head -1)
    if [ -n "$SRC" ] && [ -f "$SRC" ]; then
        cp "$SRC" "$DATASET"
        echo "Copied from flatpak data library: $SRC"
    else
        # Fallback: download from JASP GitHub repository
        echo "Flatpak data library not found, downloading from GitHub..."
        wget -q -O "$DATASET" \
            "https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/3.%20ANOVA/Heart%20Rate.csv"
    fi

    chown ga:ga "$DATASET"
    chmod 644 "$DATASET"
fi

# Validate the dataset
DATASET_SIZE=$(stat -c%s "$DATASET" 2>/dev/null || echo 0)
if [ "$DATASET_SIZE" -lt 500 ]; then
    echo "ERROR: HeartRate.csv is too small or missing (${DATASET_SIZE} bytes)"
    exit 1
fi
echo "Dataset ready: $DATASET (${DATASET_SIZE} bytes)"
head -3 "$DATASET"

# -----------------------------------------------------------
# Record baseline state for verifier
# -----------------------------------------------------------
echo "$(date +%s)" > /tmp/task_start_timestamp
ls -la /home/ga/Documents/JASP/ > /tmp/task_baseline_files.txt 2>/dev/null || true

# -----------------------------------------------------------
# Launch JASP with the Heart Rate dataset pre-loaded
# Uses setsid so the process survives when su exits
# -----------------------------------------------------------
su - ga -c "setsid /usr/local/bin/launch-jasp '$DATASET' > /tmp/jasp_task.log 2>&1 &"
sleep 22

# Dismiss any startup dialogs (update check, etc.)
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 2

# Maximize the JASP window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

echo "=== nonparametric_group_comparison task setup complete ==="
