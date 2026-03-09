#!/bin/bash
echo "=== Setting up Calculate Segment Statistics Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
SAMPLE_ID="${1:-BraTS2021_00000}"

# Create directories
mkdir -p "$BRATS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
mkdir -p "$EXPORTS_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Clear any previous output files
rm -f "$EXPORTS_DIR/tumor_statistics.csv" 2>/dev/null || true
rm -f /tmp/segstats_result.json 2>/dev/null || true

# Record initial state
echo "0" > /tmp/initial_csv_exists
if [ -f "$EXPORTS_DIR/tumor_statistics.csv" ]; then
    echo "1" > /tmp/initial_csv_exists
    stat -c %Y "$EXPORTS_DIR/tumor_statistics.csv" > /tmp/initial_csv_mtime
fi

# ============================================================
# Prepare BraTS data
# ============================================================
echo "Preparing BraTS data..."
/workspace/scripts/prepare_brats_data.sh "$SAMPLE_ID"

# Get the actual sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
fi
echo "$SAMPLE_ID" > /tmp/task_sample_id

CASE_DIR="$BRATS_DIR/$SAMPLE_ID"
T1CE_FILE="$CASE_DIR/${SAMPLE_ID}_t1ce.nii.gz"
SEG_FILE="$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"

# Verify data exists
if [ ! -f "$T1CE_FILE" ]; then
    echo "ERROR: T1ce file not found at $T1CE_FILE"
    exit 1
fi

if [ ! -f "$SEG_FILE" ]; then
    echo "ERROR: Segmentation file not found at $SEG_FILE"
    exit 1
fi

echo "T1ce file: $T1CE_FILE"
echo "Segmentation file: $SEG_FILE"

# ============================================================
# Compute ground truth statistics for verification
# ============================================================
echo "Computing ground truth statistics..."

python3 << PYEOF
import os
import sys
import json
import numpy as np

try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

sample_id = "$SAMPLE_ID"
t1ce_path = "$T1CE_FILE"
seg_path = "$SEG_FILE"
gt_dir = "$GROUND_TRUTH_DIR"

print(f"Loading T1ce volume: {t1ce_path}")
t1ce_nii = nib.load(t1ce_path)
t1ce_data = t1ce_nii.get_fdata()
voxel_dims = t1ce_nii.header.get_zooms()[:3]
voxel_volume_mm3 = float(np.prod(voxel_dims))

print(f"Loading segmentation: {seg_path}")
seg_nii = nib.load(seg_path)
seg_data = seg_nii.get_fdata().astype(np.int32)

print(f"T1ce shape: {t1ce_data.shape}")
print(f"Segmentation shape: {seg_data.shape}")
print(f"Voxel volume: {voxel_volume_mm3:.4f} mm³")

# BraTS labels: 0=background, 1=necrotic, 2=edema, 4=enhancing
# Note: label 3 is not used in BraTS
label_map = {
    1: "Necrotic",
    2: "Edema", 
    4: "Enhancing"
}

stats = {
    "sample_id": sample_id,
    "voxel_volume_mm3": voxel_volume_mm3,
    "segments": {}
}

for label, name in label_map.items():
    mask = (seg_data == label)
    voxel_count = int(np.sum(mask))
    
    if voxel_count > 0:
        volume_mm3 = voxel_count * voxel_volume_mm3
        volume_cm3 = volume_mm3 / 1000.0
        
        # Intensity statistics from T1ce
        intensities = t1ce_data[mask]
        mean_intensity = float(np.mean(intensities))
        std_intensity = float(np.std(intensities))
        min_intensity = float(np.min(intensities))
        max_intensity = float(np.max(intensities))
        median_intensity = float(np.median(intensities))
        
        stats["segments"][name] = {
            "voxel_count": voxel_count,
            "volume_mm3": volume_mm3,
            "volume_cm3": volume_cm3,
            "mean_intensity": mean_intensity,
            "std_intensity": std_intensity,
            "min_intensity": min_intensity,
            "max_intensity": max_intensity,
            "median_intensity": median_intensity
        }
        
        print(f"{name}: {voxel_count} voxels, {volume_mm3:.2f} mm³ ({volume_cm3:.2f} cm³), mean={mean_intensity:.2f}")
    else:
        print(f"{name}: No voxels found (label {label})")
        stats["segments"][name] = {
            "voxel_count": 0,
            "volume_mm3": 0,
            "volume_cm3": 0
        }

# Calculate total tumor volume
total_voxels = sum(s.get("voxel_count", 0) for s in stats["segments"].values())
total_volume_mm3 = sum(s.get("volume_mm3", 0) for s in stats["segments"].values())
stats["total_tumor_voxels"] = total_voxels
stats["total_tumor_volume_mm3"] = total_volume_mm3
stats["total_tumor_volume_cm3"] = total_volume_mm3 / 1000.0

print(f"\nTotal tumor: {total_voxels} voxels, {total_volume_mm3:.2f} mm³")

# Save ground truth for verification
gt_path = os.path.join(gt_dir, f"{sample_id}_segment_stats_gt.json")
with open(gt_path, "w") as f:
    json.dump(stats, f, indent=2)
print(f"\nGround truth saved to: {gt_path}")

# Also save to /tmp for verifier access
with open("/tmp/segment_stats_gt.json", "w") as f:
    json.dump(stats, f, indent=2)
PYEOF

# ============================================================
# Copy segmentation to accessible location for Slicer
# ============================================================
# Create a labeled segmentation that Slicer can load
LABELED_SEG="$CASE_DIR/${SAMPLE_ID}_tumor_seg.nii.gz"
if [ ! -f "$LABELED_SEG" ]; then
    cp "$SEG_FILE" "$LABELED_SEG"
    chown ga:ga "$LABELED_SEG"
fi

# ============================================================
# Launch 3D Slicer and load data
# ============================================================
echo "Launching 3D Slicer with BraTS data..."

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create a Python script to load the data and set up segmentation
LOAD_SCRIPT="/tmp/load_brats_segstats.py"
cat > "$LOAD_SCRIPT" << 'PYEOF'
import slicer
import os
import time

sample_id = os.environ.get("SAMPLE_ID", "BraTS2021_00000")
brats_dir = os.environ.get("BRATS_DIR", "/home/ga/Documents/SlicerData/BraTS")
case_dir = os.path.join(brats_dir, sample_id)

t1ce_path = os.path.join(case_dir, f"{sample_id}_t1ce.nii.gz")
seg_path = os.path.join(case_dir, f"{sample_id}_tumor_seg.nii.gz")

print(f"Loading T1ce: {t1ce_path}")
print(f"Loading Segmentation: {seg_path}")

# Load the T1ce volume
if os.path.exists(t1ce_path):
    t1ce_node = slicer.util.loadVolume(t1ce_path)
    t1ce_node.SetName("T1ce_MRI")
    print(f"Loaded T1ce volume: {t1ce_node.GetName()}")
else:
    print(f"ERROR: T1ce file not found: {t1ce_path}")

# Load the segmentation
if os.path.exists(seg_path):
    # Load as labelmap first
    labelmap_node = slicer.util.loadLabelVolume(seg_path)
    labelmap_node.SetName("TumorLabels")
    
    # Create a segmentation node from the labelmap
    seg_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLSegmentationNode")
    seg_node.SetName("TumorSegmentation")
    
    # Import labelmap to segmentation
    slicer.modules.segmentations.logic().ImportLabelmapToSegmentationNode(labelmap_node, seg_node)
    
    # Rename segments according to BraTS convention
    segmentation = seg_node.GetSegmentation()
    
    # BraTS labels: 1=necrotic, 2=edema, 4=enhancing
    segment_names = {
        "1": "Necrotic",
        "2": "Edema",
        "4": "Enhancing"
    }
    
    for i in range(segmentation.GetNumberOfSegments()):
        segment_id = segmentation.GetNthSegmentID(i)
        segment = segmentation.GetSegment(segment_id)
        old_name = segment.GetName()
        
        # Try to match by label value in name
        for label, new_name in segment_names.items():
            if label in old_name or old_name == label:
                segment.SetName(new_name)
                print(f"Renamed segment '{old_name}' to '{new_name}'")
                break
    
    # Remove the temporary labelmap
    slicer.mrmlScene.RemoveNode(labelmap_node)
    
    print(f"Created segmentation with {segmentation.GetNumberOfSegments()} segments")
else:
    print(f"ERROR: Segmentation file not found: {seg_path}")

# Set up the views
slicer.app.layoutManager().setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutFourUpView)

# Center the views on the data
slicer.util.resetSliceViews()

print("Data loading complete")
PYEOF

chown ga:ga "$LOAD_SCRIPT"

# Launch Slicer with the loading script
export SAMPLE_ID BRATS_DIR
su - ga -c "DISPLAY=:1 SAMPLE_ID='$SAMPLE_ID' BRATS_DIR='$BRATS_DIR' /opt/Slicer/Slicer --python-script '$LOAD_SCRIPT' > /tmp/slicer_load.log 2>&1 &"

# Wait for Slicer to start and load data
echo "Waiting for 3D Slicer to start and load data..."
sleep 15

# Wait for Slicer window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Additional wait for data loading
sleep 10

# Maximize and focus Slicer
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial screenshot..."
take_screenshot /tmp/segstats_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo "Sample ID: $SAMPLE_ID"
echo "T1ce Volume: Loaded as 'T1ce_MRI'"
echo "Segmentation: Loaded as 'TumorSegmentation' with segments:"
echo "  - Necrotic (necrotic tumor core)"
echo "  - Edema (peritumoral edema)"  
echo "  - Enhancing (enhancing tumor)"
echo ""
echo "TASK: Calculate segment statistics and export to:"
echo "  ~/Documents/SlicerData/Exports/tumor_statistics.csv"
echo ""
echo "Use Modules → Quantification → Segment Statistics"