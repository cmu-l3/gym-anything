#!/bin/bash
set -e
echo "=== Setting up anova_trend_analysis_viagra task ==="

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Prepare Data
DATA_SRC="/opt/jamovi_datasets/Viagra.csv"
DATA_DEST="/home/ga/Documents/Jamovi/Viagra.csv"

mkdir -p /home/ga/Documents/Jamovi
if [ -f "$DATA_SRC" ]; then
    cp "$DATA_SRC" "$DATA_DEST"
    chown ga:ga "$DATA_DEST"
    chmod 644 "$DATA_DEST"
    echo "Dataset placed at $DATA_DEST"
else
    echo "ERROR: Source dataset $DATA_SRC not found!"
    exit 1
fi

# 3. Clean up previous artifacts
rm -f /home/ga/Documents/Jamovi/Viagra_TrendAnalysis.omv
rm -f /home/ga/Documents/Jamovi/trend_report.txt

# 4. Start Jamovi (Clean State)
# Kill any running instances first
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Launch Jamovi (empty)
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_launch.log 2>&1 &"

# Wait for window
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
        echo "Jamovi window detected"
        break
    fi
    sleep 1
done

# 5. Maximize window (Critical for VLM/Agent)
# Note: Jamovi's window title often changes based on open file, but initially it usually contains "jamovi"
sleep 5
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="