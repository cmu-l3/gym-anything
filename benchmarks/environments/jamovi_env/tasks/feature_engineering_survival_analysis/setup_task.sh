#!/bin/bash
set -e
echo "=== Setting up feature_engineering_survival_analysis task ==="

# 1. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous runs
rm -f /home/ga/Documents/Jamovi/Titanic_FeatureEng.omv 2>/dev/null || true
rm -f /home/ga/Documents/Jamovi/survival_rates.txt 2>/dev/null || true

# 3. Ensure Dataset Exists
DATASET="/home/ga/Documents/Jamovi/TitanicSurvival.csv"
if [ ! -f "$DATASET" ]; then
    echo "Restoring dataset from /opt/jamovi_datasets..."
    mkdir -p /home/ga/Documents/Jamovi
    cp "/opt/jamovi_datasets/TitanicSurvival.csv" "$DATASET"
    chown ga:ga "$DATASET"
    chmod 644 "$DATASET"
fi

# 4. Start Jamovi with the dataset loaded
# Using setsid to detach from the shell so it persists
echo "Starting Jamovi..."
if ! pgrep -f "org.jamovi.jamovi" > /dev/null; then
    su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATASET' > /tmp/jamovi.log 2>&1 &"
    
    # Wait for window to appear (Jamovi Electron app takes time)
    echo "Waiting for Jamovi window..."
    for i in {1..40}; do
        if DISPLAY=:1 wmctrl -l | grep -i "TitanicSurvival"; then
            echo "Jamovi window detected."
            break
        fi
        sleep 1
    done
fi

# 5. Window Management
# Maximize the window to ensure all controls are visible to the agent
# Using :ACTIVE: or searching by title
sleep 5
DISPLAY=:1 wmctrl -r "TitanicSurvival" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "TitanicSurvival" 2>/dev/null || true

# 6. Initial Screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="