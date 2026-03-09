#!/bin/bash
echo "=== Setting up Resample Isotropic Volume Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ============================================================
# Prepare AMOS abdominal CT data
# ============================================================
AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

echo "Preparing abdominal CT data..."
mkdir -p "$AMOS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Run data preparation script
export AMOS_DIR GROUND_TRUTH_DIR CASE_ID
bash /workspace/scripts/prepare_amos_data.sh "$CASE_ID" 2>&1 || {
    echo "WARNING: Data preparation script had issues, checking if data exists..."
}

# Get the case ID that was actually used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
fi

CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"

# Verify CT file exists
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT file not found at $CT_FILE"
    echo "Available files in AMOS dir:"
    ls -la "$AMOS_DIR/" 2>/dev/null || echo "Directory does not exist"
    exit 1
fi

echo "CT file ready: $CT_FILE"
echo "File size: $(du -h "$CT_FILE" | cut -f1)"

# ============================================================
# Record initial volume state for verification
# ============================================================
echo "Recording initial volume state..."

python3 << 'PYEOF'
import os
import json
import sys

try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

case_id = os.environ.get("CASE_ID", "amos_0001")
amos_dir = os.environ.get("AMOS_DIR", "/home/ga/Documents/SlicerData/AMOS")
ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")

try:
    nii = nib.load(ct_path)
    spacing = list(nii.header.get_zooms()[:3])
    dims = list(nii.shape[:3])
    
    # Check if anisotropic (z-spacing > 1.5x other spacings)
    max_sp = max(spacing)
    min_sp = min(spacing)
    is_anisotropic = (max_sp / min_sp) > 1.5 if min_sp > 0 else False
    
    initial_state = {
        "case_id": case_id,
        "ct_file": ct_path,
        "original_spacing_mm": [float(s) for s in spacing],
        "original_dimensions": [int(d) for d in dims],
        "is_anisotropic": is_anisotropic,
        "anisotropy_ratio": float(max_sp / min_sp) if min_sp > 0 else 0
    }
    
    with open("/tmp/initial_volume_state.json", "w") as f:
        json.dump(initial_state, f, indent=2)
    
    print(f"Initial volume state recorded:")
    print(f"  Spacing (mm): {spacing}")
    print(f"  Dimensions: {dims}")
    print(f"  Anisotropic: {is_anisotropic} (ratio: {initial_state['anisotropy_ratio']:.2f})")
    
except Exception as e:
    print(f"ERROR recording initial state: {e}")
    # Create minimal state file
    with open("/tmp/initial_volume_state.json", "w") as f:
        json.dump({"error": str(e), "case_id": case_id}, f)
PYEOF

# ============================================================
# Kill any existing Slicer and launch fresh
# ============================================================
echo "Launching 3D Slicer with CT data..."

pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the CT file
export DISPLAY=:1
xhost +local: 2>/dev/null || true

sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer "$CT_FILE" > /tmp/slicer_launch.log 2>&1 &
SLICER_PID=$!

echo "Slicer launched with PID: $SLICER_PID"

# ============================================================
# Wait for Slicer to fully load
# ============================================================
echo "Waiting for 3D Slicer to start..."

# Wait for window to appear
for i in $(seq 1 60); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer\|3D Slicer"; then
        echo "3D Slicer window detected after ${i}s"
        break
    fi
    sleep 2
done

# Additional wait for data to load
echo "Waiting for volume to load..."
sleep 10

# Wait for Slicer to finish loading (window title should contain volume name or "Welcome")
for i in $(seq 1 30); do
    TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "")
    if echo "$TITLE" | grep -qiE "Slicer.*[0-9]|amos|Welcome|Volumes"; then
        echo "Slicer appears fully loaded (title: $TITLE)"
        break
    fi
    sleep 2
done

# ============================================================
# Maximize and focus Slicer window
# ============================================================
SLICER_WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "slicer" | head -1 | awk '{print $1}')
if [ -n "$SLICER_WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$SLICER_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$SLICER_WID" 2>/dev/null || true
    echo "Slicer window maximized and focused"
else
    echo "WARNING: Could not find Slicer window to maximize"
fi

sleep 3

# ============================================================
# Take initial screenshot
# ============================================================
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# ============================================================
# Final setup summary
# ============================================================
echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "LOADED DATA:"
echo "  CT File: $CT_FILE"
INITIAL_SPACING=$(python3 -c "import json; d=json.load(open('/tmp/initial_volume_state.json')); print(d.get('original_spacing_mm', []))" 2>/dev/null || echo "unknown")
INITIAL_DIMS=$(python3 -c "import json; d=json.load(open('/tmp/initial_volume_state.json')); print(d.get('original_dimensions', []))" 2>/dev/null || echo "unknown")
echo "  Original Spacing: $INITIAL_SPACING mm"
echo "  Original Dimensions: $INITIAL_DIMS"
echo ""
echo "TASK GOAL:"
echo "  Resample this volume to isotropic 1.0mm × 1.0mm × 1.0mm spacing"
echo "  Output volume should be named 'CT_Isotropic'"
echo ""
echo "HINT: Use Modules → Filtering → Resample Scalar/Vector/DWI Volume"
echo "      Or search for 'resample' in the module search"
echo ""