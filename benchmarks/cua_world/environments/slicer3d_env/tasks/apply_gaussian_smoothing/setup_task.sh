#!/bin/bash
echo "=== Setting up Gaussian Smoothing Task ==="

# Source common utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

SAMPLE_DATA_DIR="/home/ga/Documents/SlicerData/SampleData"
RESULT_DIR="/tmp/slicer_task_results"
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"

mkdir -p "$RESULT_DIR"
mkdir -p "$EXPORT_DIR"
chmod 777 "$RESULT_DIR"
chmod 777 "$EXPORT_DIR"

# ============================================================
# Ensure MRHead sample data exists (with robust retry logic)
# ============================================================
MRHEAD_OK=false
if [ -f "$SAMPLE_DATA_DIR/MRHead.nrrd" ] && [ $(stat -c%s "$SAMPLE_DATA_DIR/MRHead.nrrd" 2>/dev/null || echo 0) -gt 1000000 ]; then
    MRHEAD_OK=true
fi

if [ "$MRHEAD_OK" = "false" ]; then
    echo "MRHead sample data not found or invalid. Attempting to download..."
    mkdir -p "$SAMPLE_DATA_DIR"
    cd "$SAMPLE_DATA_DIR"
    rm -f MRHead.nrrd 2>/dev/null

    # Try multiple URLs with retries
    for attempt in 1 2 3; do
        echo "Download attempt $attempt..."

        # Try primary URL (GitHub)
        curl -L -o MRHead.nrrd --connect-timeout 30 --max-time 180 --retry 2 \
            "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null

        if [ -f MRHead.nrrd ] && [ $(stat -c%s MRHead.nrrd 2>/dev/null || echo 0) -gt 1000000 ]; then
            echo "Download successful on attempt $attempt"
            MRHEAD_OK=true
            break
        fi
        rm -f MRHead.nrrd 2>/dev/null

        # Try alternative URL (Kitware)
        wget --timeout=180 --tries=2 -O MRHead.nrrd \
            "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null

        if [ -f MRHead.nrrd ] && [ $(stat -c%s MRHead.nrrd 2>/dev/null || echo 0) -gt 1000000 ]; then
            echo "Download successful on attempt $attempt (alt URL)"
            MRHEAD_OK=true
            break
        fi
        rm -f MRHead.nrrd 2>/dev/null

        sleep 3
    done

    chown -R ga:ga "$SAMPLE_DATA_DIR" 2>/dev/null || true
fi

if [ "$MRHEAD_OK" = "false" ]; then
    echo "WARNING: MRHead.nrrd could not be downloaded. Generating synthetic data..."
    python3 << 'SYNTHEOF'
import numpy as np
import os

shape = (64, 64, 64)
data = np.zeros(shape, dtype=np.int16)
center = np.array(shape) / 2
for x in range(shape[0]):
    for y in range(shape[1]):
        for z in range(shape[2]):
            dist = np.sqrt((x - center[0])**2 + (y - center[1])**2 + (z - center[2])**2)
            if dist < 25:
                data[x, y, z] = 800 + int(200 * np.sin(dist / 3))
            elif dist < 28:
                data[x, y, z] = 1200

out_path = "/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd"
with open(out_path, 'wb') as f:
    header = "NRRD0004\ntype: int16\ndimension: 3\nspace: left-posterior-superior\nsizes: 64 64 64\nspace directions: (2,0,0) (0,2,0) (0,0,2)\nkinds: domain domain domain\nendian: little\nencoding: raw\nspace origin: (-64,-64,-64)\n\n"
    f.write(header.encode('ascii'))
    f.write(data.tobytes())
print("Created synthetic MRHead.nrrd")
SYNTHEOF
    chown ga:ga "$SAMPLE_DATA_DIR/MRHead.nrrd" 2>/dev/null || true
fi

# Verify file exists (don't exit on failure - Slicer can still launch without data)
FILE_SIZE=$(stat -c%s "$SAMPLE_DATA_DIR/MRHead.nrrd" 2>/dev/null || echo 0)
if [ "$FILE_SIZE" -lt 1000 ]; then
    echo "WARNING: MRHead.nrrd is missing or too small (${FILE_SIZE} bytes)"
else
    echo "MRHead sample data verified: ${FILE_SIZE} bytes"
fi

echo "MRHead sample data verified: $(du -h "$SAMPLE_DATA_DIR/MRHead.nrrd")"

# ============================================================
# Record initial state for comparison
# Compute statistics of input volume for verification
# ============================================================
echo "Computing initial volume statistics..."

python3 << 'PYEOF'
import numpy as np
import json
import os
import sys

# Ensure pynrrd is available
try:
    import nrrd
except ImportError:
    import subprocess
    subprocess.call([sys.executable, "-m", "pip", "install", "-q", "pynrrd"], timeout=60)
    import nrrd

# Ensure scipy is available
try:
    from scipy.ndimage import laplace
except ImportError:
    import subprocess
    subprocess.call([sys.executable, "-m", "pip", "install", "-q", "scipy"], timeout=120)
    from scipy.ndimage import laplace

sample_dir = "/home/ga/Documents/SlicerData/SampleData"
result_dir = "/tmp/slicer_task_results"

mrhead_path = os.path.join(sample_dir, "MRHead.nrrd")

print(f"Loading MRHead from {mrhead_path}...")
data, header = nrrd.read(mrhead_path)

print(f"Volume shape: {data.shape}")
print(f"Volume dtype: {data.dtype}")

# Compute statistics for later comparison
data_float = data.astype(np.float32)
laplacian_mag = np.abs(laplace(data_float)).mean()

initial_stats = {
    "shape": list(data.shape),
    "dtype": str(data.dtype),
    "min": float(data.min()),
    "max": float(data.max()),
    "mean": float(data.mean()),
    "std": float(data.std()),
    "laplacian_mean": float(laplacian_mag),
    "total_voxels": int(np.prod(data.shape)),
    "file_path": mrhead_path,
    "file_size_bytes": os.path.getsize(mrhead_path)
}

stats_path = os.path.join(result_dir, "initial_stats.json")
with open(stats_path, "w") as f:
    json.dump(initial_stats, f, indent=2)

print(f"Initial volume statistics saved to {stats_path}")
print(f"  Shape: {initial_stats['shape']}")
print(f"  Range: [{initial_stats['min']:.1f}, {initial_stats['max']:.1f}]")
print(f"  Mean: {initial_stats['mean']:.2f}")
print(f"  Std: {initial_stats['std']:.2f}")
print(f"  Laplacian mean (edge sharpness): {initial_stats['laplacian_mean']:.4f}")
PYEOF

if [ $? -ne 0 ]; then
    echo "WARNING: Failed to compute initial statistics, continuing anyway"
fi

# ============================================================
# Kill any existing Slicer instances and launch fresh
# ============================================================
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# ============================================================
# Launch 3D Slicer with MRHead loaded
# ============================================================
echo "Launching 3D Slicer with MRHead volume..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer "$SAMPLE_DATA_DIR/MRHead.nrrd" > /tmp/slicer_task.log 2>&1 &

# Wait for Slicer to fully load
echo "Waiting for 3D Slicer to start and load data..."
wait_for_slicer 90

if [ $? -ne 0 ]; then
    echo "WARNING: Slicer may not have fully loaded"
fi

# Focus and maximize Slicer window
sleep 3
WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    echo "Slicer window found: $WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
else
    echo "WARNING: Could not find Slicer window"
fi

# Dismiss any startup dialogs
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Record list of current volumes in scene (should just be MRHead)
echo "Recording initial scene state..."
cat > /tmp/check_initial_volumes.py << 'PYEOF'
import json
try:
    import slicer
    volumes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
    vol_names = [v.GetName() for v in volumes]
    with open("/tmp/slicer_task_results/initial_volumes.json", "w") as f:
        json.dump({"volumes": vol_names, "count": len(vol_names)}, f)
    print(f"Initial volumes: {vol_names}")
except Exception as e:
    print(f"Could not query Slicer: {e}")
PYEOF

# Try to run the check script in Slicer (may not work if Slicer isn't ready)
sudo -u ga DISPLAY=:1 timeout 10 /opt/Slicer/Slicer --no-splash --python-script /tmp/check_initial_volumes.py 2>/dev/null &
sleep 5

# Take initial screenshot
mkdir -p /home/ga/Documents/SlicerData/Screenshots
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
    cp /tmp/task_initial.png /home/ga/Documents/SlicerData/Screenshots/task_initial.png 2>/dev/null || true
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Gaussian Smoothing Task Setup Complete ==="
echo ""
echo "TASK: Apply Gaussian smoothing filter to the loaded MRHead brain MRI"
echo ""
echo "Instructions:"
echo "  1. Navigate to: Modules → Filtering → Simple Filters (or search for 'Simple Filters')"
echo "  2. Select filter: 'DiscreteGaussianImageFilter' or 'SmoothingRecursiveGaussianImageFilter'"
echo "  3. Set Input Volume: MRHead"
echo "  4. Create Output Volume: MRHead_smoothed"
echo "  5. Set Sigma: ~2.0 mm"
echo "  6. Click 'Apply'"
echo ""
echo "The smoothed volume should have visibly reduced noise/graininess."