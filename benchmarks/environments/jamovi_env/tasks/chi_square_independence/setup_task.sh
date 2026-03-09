#!/bin/bash
set -e
echo "=== Setting up Chi-Square Independence task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure the Documents directory exists
mkdir -p /home/ga/Documents/Jamovi

# Ensure the dataset exists in the user's documents
# The environment install script places datasets in /opt/jamovi_datasets
DATASET_SOURCE="/opt/jamovi_datasets/TitanicSurvival.csv"
DATASET_DEST="/home/ga/Documents/Jamovi/TitanicSurvival.csv"

if [ -f "$DATASET_SOURCE" ]; then
    cp "$DATASET_SOURCE" "$DATASET_DEST"
    chown ga:ga "$DATASET_DEST"
    echo "Dataset copied to $DATASET_DEST"
else
    echo "ERROR: Source dataset not found at $DATASET_SOURCE"
    # Fallback creation if missing (should not happen in correct env)
    echo "Unnamed: 0,survived,sex,age,passengerClass" > "$DATASET_DEST"
    echo "Allen, Miss. Elisabeth Walton,yes,female,29,1st" >> "$DATASET_DEST"
    chown ga:ga "$DATASET_DEST"
fi

# Clean up previous run artifacts
rm -f /home/ga/Documents/Jamovi/TitanicChiSquare.omv
rm -f /home/ga/Documents/Jamovi/chisquare_report.txt

# Start Jamovi
# We launch it empty so the agent has to open the file (part of the task)
# or we could launch it with the file. The description says "Open ... if not already open",
# but giving them the app open is polite.
echo "Starting Jamovi..."
if ! pgrep -f "org.jamovi.jamovi" > /dev/null; then
    su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi.log 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
            echo "Jamovi window detected"
            break
        fi
        sleep 1
    done
fi

# Maximize the window
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="