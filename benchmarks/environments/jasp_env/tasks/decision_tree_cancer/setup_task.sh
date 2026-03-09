#!/bin/bash
set -e
echo "=== Setting up Decision Tree task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create data directory
DATA_DIR="/home/ga/Documents/JASP"
mkdir -p "$DATA_DIR"

# Check if dataset needs to be downloaded and processed
if [ ! -f "$DATA_DIR/BreastCancer.csv" ]; then
    echo "Downloading and processing Breast Cancer dataset..."
    
    # Download raw data from UCI (no headers)
    curl -L -s -o "$DATA_DIR/wdbc.data" \
        "https://archive.ics.uci.edu/ml/machine-learning-databases/breast-cancer-wisconsin/wdbc.data"

    # Add headers via Python
    python3 -c '
import csv
import os

input_path = "'"$DATA_DIR"'/wdbc.data"
output_path = "'"$DATA_DIR"'/BreastCancer.csv"

headers = [
    "ID", "Diagnosis",
    "RadiusMean", "TextureMean", "PerimeterMean", "AreaMean", "SmoothnessMean", 
    "CompactnessMean", "ConcavityMean", "PointsMean", "SymmetryMean", "FractalDimensionMean",
    "RadiusSE", "TextureSE", "PerimeterSE", "AreaSE", "SmoothnessSE", 
    "CompactnessSE", "ConcavitySE", "PointsSE", "SymmetrySE", "FractalDimensionSE",
    "RadiusWorst", "TextureWorst", "PerimeterWorst", "AreaWorst", "SmoothnessWorst", 
    "CompactnessWorst", "ConcavityWorst", "PointsWorst", "SymmetryWorst", "FractalDimensionWorst"
]

if os.path.exists(input_path):
    data = []
    with open(input_path, "r") as f:
        reader = csv.reader(f)
        for row in reader:
            if row: data.append(row)
    
    with open(output_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(headers)
        writer.writerows(data)
    print(f"Processed {len(data)} rows to {output_path}")
else:
    print("Error: Input file not found")
'
    rm -f "$DATA_DIR/wdbc.data"
    chown ga:ga "$DATA_DIR/BreastCancer.csv"
fi

echo "Dataset ready at $DATA_DIR/BreastCancer.csv"

# Start JASP
echo "Starting JASP..."
# Kill any existing instances
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

# Launch JASP
su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp_launch.log 2>&1 &"

# Wait for window
echo "Waiting for JASP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP" > /dev/null; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# Maximize window
sleep 5
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss any startup dialogs
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="