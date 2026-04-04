#!/bin/bash
echo "=== Setting up Tumor Histogram Heterogeneity Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Clean up any previous task artifacts
echo "Cleaning previous task artifacts..."
rm -f "$BRATS_DIR/tumor_statistics.csv" 2>/dev/null || true
rm -f "$BRATS_DIR/heterogeneity_report.json" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/heterogeneity_gt.json 2>/dev/null || true

# Prepare BraTS data (downloads real data if not exists)
echo "Preparing BraTS 2021 data..."
/workspace/scripts/prepare_brats_data.sh

# Get sample ID
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

SAMPLE_DIR="$BRATS_DIR/$SAMPLE_ID"
echo "Using sample: $SAMPLE_ID"

# Verify T1ce volume exists
T1CE_PATH="$SAMPLE_DIR/${SAMPLE_ID}_t1ce.nii.gz"
if [ ! -f "$T1CE_PATH" ]; then
    T1CE_PATH="$SAMPLE_DIR/${SAMPLE_ID}_t1.nii.gz"
fi

if [ ! -f "$T1CE_PATH" ]; then
    echo "ERROR: T1ce/T1 volume not found!"
    exit 1
fi
echo "T1ce volume found: $T1CE_PATH"

# Create tumor segmentation for the agent from ground truth
GT_SEG="$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"
AGENT_SEG="$BRATS_DIR/${SAMPLE_ID}_tumor_seg.nii.gz"

if [ -f "$GT_SEG" ]; then
    echo "Creating agent-visible tumor segmentation..."
    cp "$GT_SEG" "$AGENT_SEG"
    chown ga:ga "$AGENT_SEG" 2>/dev/null || true
    chmod 644 "$AGENT_SEG" 2>/dev/null || true
    echo "Tumor segmentation created at: $AGENT_SEG"
else
    echo "ERROR: Ground truth segmentation not found at $GT_SEG"
    exit 1
fi

# Compute ground truth statistics for verification
echo "Computing ground truth heterogeneity statistics..."
python3 << PYEOF
import os
import sys
import json
import numpy as np

# Ensure nibabel is available
try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

sample_id = "$SAMPLE_ID"
brats_dir = "$BRATS_DIR"
gt_dir = "$GROUND_TRUTH_DIR"
sample_dir = "$SAMPLE_DIR"

# Load T1ce volume
t1ce_path = "$T1CE_PATH"
print(f"Loading T1ce volume: {t1ce_path}")
t1ce_nii = nib.load(t1ce_path)
t1ce_data = t1ce_nii.get_fdata()

# Load ground truth segmentation
seg_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")
print(f"Loading segmentation: {seg_path}")
seg_nii = nib.load(seg_path)
seg_data = seg_nii.get_fdata()

# Extract tumor voxels (all non-zero labels in BraTS are tumor)
tumor_mask = seg_data > 0
tumor_intensities = t1ce_data[tumor_mask]

print(f"T1ce shape: {t1ce_data.shape}")
print(f"Tumor voxel count: {np.sum(tumor_mask)}")

if len(tumor_intensities) > 0:
    mean_val = float(np.mean(tumor_intensities))
    std_val = float(np.std(tumor_intensities))
    min_val = float(np.min(tumor_intensities))
    max_val = float(np.max(tumor_intensities))
    cv = (std_val / mean_val * 100) if mean_val != 0 else 0
    
    # Classify heterogeneity
    if cv < 20:
        het_class = "Homogeneous"
    elif cv < 35:
        het_class = "Mildly Heterogeneous"
    elif cv < 50:
        het_class = "Moderately Heterogeneous"
    else:
        het_class = "Highly Heterogeneous"
    
    gt_stats = {
        "sample_id": sample_id,
        "mean_intensity": round(mean_val, 4),
        "std_intensity": round(std_val, 4),
        "min_intensity": round(min_val, 4),
        "max_intensity": round(max_val, 4),
        "coefficient_of_variation_percent": round(cv, 4),
        "heterogeneity_class": het_class,
        "tumor_voxel_count": int(np.sum(tumor_mask))
    }
    
    # Save to ground truth directory (hidden from agent)
    gt_path = os.path.join(gt_dir, f"{sample_id}_heterogeneity_gt.json")
    with open(gt_path, 'w') as f:
        json.dump(gt_stats, f, indent=2)
    
    # Also save to /tmp for verification
    with open("/tmp/heterogeneity_gt.json", 'w') as f:
        json.dump(gt_stats, f, indent=2)
    
    print(f"\nGround truth statistics computed:")
    print(f"  Mean intensity: {mean_val:.2f}")
    print(f"  Std deviation: {std_val:.2f}")
    print(f"  Min intensity: {min_val:.2f}")
    print(f"  Max intensity: {max_val:.2f}")
    print(f"  CV: {cv:.2f}%")
    print(f"  Heterogeneity class: {het_class}")
    print(f"\nGround truth saved to: {gt_path}")
else:
    print("ERROR: No tumor voxels found in segmentation!")
    sys.exit(1)
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to compute ground truth statistics"
    exit 1
fi

# Ensure output directory permissions
mkdir -p "$BRATS_DIR"
chown -R ga:ga "$BRATS_DIR" 2>/dev/null || true
chmod -R 755 "$BRATS_DIR" 2>/dev/null || true

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create a Slicer Python script to load the T1ce volume
cat > /tmp/load_t1ce_for_heterogeneity.py << 'PYEOF'
import slicer
import os

sample_id = os.environ.get("SAMPLE_ID", "BraTS2021_00000")
t1ce_path = os.environ.get("T1CE_PATH", "")
brats_dir = os.environ.get("BRATS_DIR", "/home/ga/Documents/SlicerData/BraTS")

print(f"Loading T1ce volume for heterogeneity analysis...")
print(f"Sample ID: {sample_id}")
print(f"T1ce path: {t1ce_path}")

if os.path.exists(t1ce_path):
    volume_node = slicer.util.loadVolume(t1ce_path)
    if volume_node:
        volume_node.SetName("T1_Contrast")
        print(f"T1ce volume loaded: {volume_node.GetName()}")
        
        # Set as background volume
        for color in ["Red", "Green", "Yellow"]:
            sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
            sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
        
        slicer.util.resetSliceViews()
        
        # Center on data
        bounds = [0]*6
        volume_node.GetBounds(bounds)
        for color in ["Red", "Green", "Yellow"]:
            sliceWidget = slicer.app.layoutManager().sliceWidget(color)
            sliceLogic = sliceWidget.sliceLogic()
            sliceNode = sliceLogic.GetSliceNode()
            center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
            if color == "Red":
                sliceNode.SetSliceOffset(center[2])
            elif color == "Green":
                sliceNode.SetSliceOffset(center[1])
            else:
                sliceNode.SetSliceOffset(center[0])
        
        print("T1ce volume ready for analysis")
    else:
        print("ERROR: Failed to load T1ce volume")
else:
    print(f"ERROR: T1ce file not found: {t1ce_path}")

print("\nSetup complete - ready for heterogeneity analysis task")
print(f"Tumor segmentation available at: {brats_dir}/{sample_id}_tumor_seg.nii.gz")
PYEOF

# Export environment variables for the Python script
export SAMPLE_ID
export T1CE_PATH
export BRATS_DIR

# Launch Slicer with the Python script
echo "Launching 3D Slicer with T1ce volume..."
sudo -u ga DISPLAY=:1 SAMPLE_ID="$SAMPLE_ID" T1CE_PATH="$T1CE_PATH" BRATS_DIR="$BRATS_DIR" \
    /opt/Slicer/Slicer --python-script /tmp/load_t1ce_for_heterogeneity.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 10

# Configure window for optimal agent interaction
echo "Configuring Slicer window..."
sleep 3

WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    focus_window "$WID"
    
    # Maximize the window
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    # Re-focus and ensure maximized
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volume to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Tumor Histogram Heterogeneity Analysis"
echo "============================================="
echo ""
echo "Sample ID: $SAMPLE_ID"
echo "T1ce volume loaded in Slicer"
echo ""
echo "Your goals:"
echo "  1. Load the tumor segmentation from:"
echo "     $BRATS_DIR/${SAMPLE_ID}_tumor_seg.nii.gz"
echo ""
echo "  2. Use Segment Statistics module (Quantification category)"
echo "     - Set T1_Contrast as scalar volume"
echo "     - Set tumor segmentation as input"
echo "     - Compute histogram statistics"
echo ""
echo "  3. Record: Mean, SD, Min, Max intensities"
echo ""
echo "  4. Calculate CV = (SD/Mean) × 100%"
echo ""
echo "  5. Classify heterogeneity:"
echo "     - Homogeneous: CV < 20%"
echo "     - Mildly Heterogeneous: CV 20-35%"
echo "     - Moderately Heterogeneous: CV 35-50%"
echo "     - Highly Heterogeneous: CV > 50%"
echo ""
echo "  6. Export statistics to: $BRATS_DIR/tumor_statistics.csv"
echo ""
echo "  7. Create JSON report at: $BRATS_DIR/heterogeneity_report.json"
echo ""