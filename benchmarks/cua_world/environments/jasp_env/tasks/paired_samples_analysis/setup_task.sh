#!/bin/bash
echo "=== Setting up paired_samples_analysis task ==="

# Kill any running JASP instance
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 3

# Ensure output directory exists
mkdir -p /home/ga/Documents/JASP
chown ga:ga /home/ga/Documents/JASP

# Copy the Weight Gain dataset from JASP's bundled Data Library (flatpak)
# The dataset is bundled with JASP and lives inside the flatpak installation.
FLATPAK_DATA="/var/lib/flatpak/app/org.jaspstats.JASP/x86_64/stable/active/files/Resources/Data Sets/Data Library/2. T-Tests/Weight Gain.csv"
DATASET="/home/ga/Documents/JASP/WeightGain.csv"

if [ ! -f "$DATASET" ]; then
    echo "Copying Weight Gain dataset from JASP Data Library..."

    # Try the active symlink first, then glob for the hash-based path
    if [ -f "$FLATPAK_DATA" ]; then
        cp "$FLATPAK_DATA" "$DATASET"
    else
        # Glob for the hash-based directory
        FOUND=$(find /var/lib/flatpak/app/org.jaspstats.JASP/x86_64/stable/ \
            -path "*/Resources/Data Sets/Data Library/2. T-Tests/Weight Gain.csv" \
            -type f 2>/dev/null | head -1)
        if [ -n "$FOUND" ]; then
            cp "$FOUND" "$DATASET"
        else
            echo "ERROR: Weight Gain dataset not found in JASP flatpak Data Library"
            echo "Searched in: /var/lib/flatpak/app/org.jaspstats.JASP/"
            # Last resort: check /opt/jasp_datasets
            if [ -f "/opt/jasp_datasets/Weight Gain.csv" ]; then
                cp "/opt/jasp_datasets/Weight Gain.csv" "$DATASET"
                echo "Copied from /opt/jasp_datasets instead"
            else
                exit 1
            fi
        fi
    fi
    chown ga:ga "$DATASET"
fi

echo "Dataset ready: $DATASET"
head -3 "$DATASET"
wc -l "$DATASET"

# Record baseline: verify no .jasp output file exists yet
OUTPUT_FILE="/home/ga/Documents/JASP/weight_gain_analysis.jasp"
if [ -f "$OUTPUT_FILE" ]; then
    echo "WARNING: Removing pre-existing output file $OUTPUT_FILE"
    rm -f "$OUTPUT_FILE"
fi

# Record task start timestamp for modification-time verification
date +%s > /tmp/paired_samples_analysis_start_ts
echo "Task start timestamp: $(cat /tmp/paired_samples_analysis_start_ts)"

# Open JASP with the dataset pre-loaded
# Uses setsid so the process survives when su exits
su - ga -c "setsid /usr/local/bin/launch-jasp $DATASET > /tmp/jasp_task.log 2>&1 &"
sleep 22

# Dismiss any dialogs (e.g. check-for-updates dialog)
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 2

# Maximize window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

echo "=== paired_samples_analysis task setup complete ==="
