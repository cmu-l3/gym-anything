#!/bin/bash
set -e

echo "=== Setting up Psychometrics Scale Construction Task ==="

# 1. Setup Data
DATA_FILE="/home/ga/Documents/Jamovi/BFI25.csv"
if [ ! -f "$DATA_FILE" ]; then
    echo "Restoring BFI25.csv..."
    # If the extract script exists, run it, otherwise copy/fail
    if [ -f "/opt/jamovi_datasets/extract_bfi25.py" ]; then
        python3 /opt/jamovi_datasets/extract_bfi25.py
    elif [ -f "/opt/jamovi_datasets/bfi.csv" ]; then
        # Fallback if python script missing (unlikely given env setup)
        cp "/opt/jamovi_datasets/bfi.csv" "$DATA_FILE"
    else
        echo "ERROR: Data source missing"
        exit 1
    fi
fi
chown ga:ga "$DATA_FILE"

# 2. Clean previous artifacts
rm -f "/home/ga/Documents/Jamovi/Extraversion_Scale.omv"
rm -f "/home/ga/Documents/Jamovi/scale_report.txt"

# 3. Record Start Time
date +%s > /tmp/task_start_time.txt

# 4. Start Jamovi
# Use system-wide launch script if available, or direct command
if command -v launch-jamovi >/dev/null; then
    CMD="launch-jamovi"
else
    # Fallback for testing environments
    CMD="flatpak run org.jamovi.jamovi -- --no-sandbox --disable-gpu"
fi

echo "Starting Jamovi..."
if ! pgrep -f "org.jamovi.jamovi" > /dev/null; then
    # Launch with the dataset pre-loaded to save agent time finding it
    # setsid ensures it runs in a new session
    su - ga -c "setsid $CMD '$DATA_FILE' > /tmp/jamovi_log.txt 2>&1 &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -i "BFI25"; then
            echo "Jamovi window detected"
            break
        fi
        sleep 1
    done
    sleep 5
fi

# 5. Maximize Window
# Note: Jamovi window title usually matches the filename "BFI25"
DISPLAY=:1 wmctrl -r "BFI25" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "BFI25" 2>/dev/null || true

# 6. Initial Screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="