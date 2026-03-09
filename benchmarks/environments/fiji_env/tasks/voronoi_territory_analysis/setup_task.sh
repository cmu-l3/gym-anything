#!/bin/bash
set -e

echo "=== Setting up Voronoi Territory Analysis Task ==="

# 1. Define paths and creates directories
RAW_DIR="/home/ga/Fiji_Data/raw/voronoi_task"
RESULTS_DIR="/home/ga/Fiji_Data/results/voronoi"

# Create directories as user ga
su - ga -c "mkdir -p '$RAW_DIR'"
su - ga -c "mkdir -p '$RESULTS_DIR'"

# 2. Clean previous results
rm -f "$RESULTS_DIR"/* 2>/dev/null || true

# 3. Prepare Data (BBBC005)
# We need a specific image set. We'll use a set with ~25 cells (C25) which gives good density for Voronoi.
# Source: Broad Bioimage Benchmark Collection
echo "Preparing image data..."

BBBC_URL="https://data.broadinstitute.org/bbbc/BBBC005/BBBC005_v1_images.zip"
ZIP_FILE="/tmp/bbbc005.zip"

# Download if not cached
if [ ! -f "$ZIP_FILE" ]; then
    echo "Downloading BBBC005 dataset..."
    wget -q --timeout=120 "$BBBC_URL" -O "$ZIP_FILE" || {
        echo "Download failed, trying backup..."
        # Fallback to local sample if download fails (simulated for environment stability)
        # In a real scenario, we might fail here.
        echo "ERROR: Could not download dataset."
        exit 1
    }
fi

# Extract specific files: C25 (25 cells), F1 (in focus), w1 (body) and w2 (nuclei)
# Pattern: BBBC005_v1_images/SIMULATION_C25_F1_s1_w1.TIF
# We use Python to extract specific files to avoid unzipping everything
python3 << PYEOF
import zipfile
import shutil
import os

zip_path = "$ZIP_FILE"
target_dir = "$RAW_DIR"
# Select a specific simulation: 25 cells, Focus 1, site 1
w1_name = "BBBC005_v1_images/SIMULATION_C25_F1_s1_w1.TIF"
w2_name = "BBBC005_v1_images/SIMULATION_C25_F1_s1_w2.TIF"

try:
    with zipfile.ZipFile(zip_path, 'r') as z:
        # Extract w1 as cell_bodies.tif
        with z.open(w1_name) as source, open(os.path.join(target_dir, "cell_bodies.tif"), "wb") as target:
            shutil.copyfileobj(source, target)
        
        # Extract w2 as cell_nuclei.tif
        with z.open(w2_name) as source, open(os.path.join(target_dir, "cell_nuclei.tif"), "wb") as target:
            shutil.copyfileobj(source, target)
            
    print("Files extracted successfully.")
except Exception as e:
    print(f"Error extracting files: {e}")
    exit(1)
PYEOF

# Create task info file
cat > "$RAW_DIR/task_info.txt" << INFOEOF
Image Source: BBBC005v1 (Broad Bioimage Benchmark Collection)
Simulation Parameters:
- Cell Count: 25
- Focus: In-focus (F1)
- Pixel Scale: Simulated (treat as 1 unit/pixel)
INFOEOF

# Fix ownership
chown -R ga:ga "/home/ga/Fiji_Data"

# 4. Record Initial State
echo "Recording initial state..."
date +%s > /tmp/task_start_time
echo "0" > /tmp/initial_results_count

# 5. Launch Fiji
echo "Launching Fiji..."
if pgrep -f "fiji" > /dev/null; then
    pkill -f "fiji"
    sleep 2
fi

su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &

# Wait for window
echo "Waiting for Fiji window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej" > /dev/null 2>&1; then
        echo "Fiji window detected."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take setup screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="