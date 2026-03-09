#!/bin/bash
set -e
echo "=== Setting up T-Test Effect Size Precision Task ==="

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous run artifacts
rm -f "/home/ga/Documents/Jamovi/ToothGrowth_EffectSize.omv"
rm -f "/home/ga/Documents/Jamovi/effect_size_report.txt"

# 3. Ensure Dataset Exists
DATASET_SOURCE="/opt/jamovi_datasets/ToothGrowth.csv"
DATASET_DEST="/home/ga/Documents/Jamovi/ToothGrowth.csv"

mkdir -p /home/ga/Documents/Jamovi

if [ ! -f "$DATASET_DEST" ]; then
    if [ -f "$DATASET_SOURCE" ]; then
        cp "$DATASET_SOURCE" "$DATASET_DEST"
    else
        # Fallback download if missing (safety net)
        wget -q -O "$DATASET_DEST" "https://raw.githubusercontent.com/vincentarelbundock/Rdatasets/master/csv/datasets/ToothGrowth.csv"
    fi
fi
# Ensure permissions
chown -R ga:ga /home/ga/Documents/Jamovi
chmod 644 "$DATASET_DEST"

# 4. Launch Jamovi (Clean State)
# We launch it empty. The agent must open the file.
if ! pgrep -f "org.jamovi.jamovi" > /dev/null; then
    echo "Starting Jamovi..."
    # Launch via system-wide script that handles sandbox flags
    su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi.log 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
            echo "Jamovi window detected"
            break
        fi
        sleep 1
    done
    sleep 5
fi

# 5. Window Management
# Maximize and focus
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# 6. Capture Initial State
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="