#!/bin/bash
echo "=== Setting up variable_metadata_labeling_bfi task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any previous run artifacts
rm -f /home/ga/Documents/Jamovi/BFI_Metadata.omv 2>/dev/null || true

# Ensure the dataset exists
DATASET_SOURCE="/opt/jamovi_datasets/BFI25.csv"
DATASET_DEST="/home/ga/Documents/Jamovi/BFI25.csv"

# The env setup script creates BFI25.csv via python script, check if it's there
if [ ! -f "$DATASET_DEST" ]; then
    echo "Generating BFI25.csv..."
    if [ -f "/opt/jamovi_datasets/extract_bfi25.py" ]; then
        python3 /opt/jamovi_datasets/extract_bfi25.py
        # Move it to correct location if script output differs
        if [ -f "/home/ga/Documents/Jamovi/BFI25.csv" ]; then
             echo "Dataset generated successfully."
        else
             echo "ERROR: Dataset generation failed."
             exit 1
        fi
    else
        echo "ERROR: Extraction script not found."
        exit 1
    fi
fi

# Ensure ownership
chown ga:ga "$DATASET_DEST"

# Launch Jamovi (empty)
# We use setsid to ensure it survives the shell exit
echo "Launching Jamovi..."
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
    sleep 5
fi

# Maximize window
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="