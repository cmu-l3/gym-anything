#!/bin/bash
echo "=== Setting up Split Segment Scissors Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Set environment variables
export PATIENT_NUM="5"
export IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
export GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Create directories
mkdir -p "$IRCADB_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Prepare IRCADb data
echo "Preparing liver CT data..."
bash /workspace/scripts/prepare_ircadb_data.sh "$PATIENT_NUM" || {
    echo "Warning: IRCADb preparation script returned error, continuing..."
}

# Verify data exists or create synthetic
PATIENT_DIR="$IRCADB_DIR/patient_${PATIENT_NUM}"
if [ ! -d "$PATIENT_DIR" ] || [ -z "$(ls -A "$PATIENT_DIR" 2>/dev/null)" ]; then
    echo "Creating synthetic liver data for testing..."
    mkdir -p "$PATIENT_DIR"
    
    python3 << 'PYEOF'
import os
import sys
import json

try:
    import numpy as np
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "numpy"])
    import numpy as np

try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

patient_dir = os.environ.get("PATIENT_DIR", "/home/ga/Documents/SlicerData/IRCADb/patient_5")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
patient_num = os.environ.get("PATIENT_NUM", "5")

np.random.seed(42)

# Create synthetic liver CT volume
nx, ny, nz = 256, 256, 100
spacing = (0.78, 0.78, 2.5)

affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

# Create CT-like data
ct_data = np.random.normal(40, 15, (nx, ny, nz)).astype(np.int16)

# Create body outline
Y, X = np.ogrid[:nx, :ny]
cx, cy = nx // 2, ny // 2
body_mask = ((X - cx)**2 / (100**2) + (Y - cy)**2 / (80**2)) <= 1.0

for z in range(nz):
    ct_data[:, :, z][~body_mask] = -1000

# Create liver region (right-biased ellipsoid)
liver_cx, liver_cy = cx - 20, cy - 15
liver_data = np.zeros((nx, ny, nz), dtype=np.int16)

for z in range(20, 85):
    z_factor = 1.0 - ((z - 52) / 35)**2
    if z_factor > 0:
        r_x = 55 * np.sqrt(z_factor)
        r_y = 45 * np.sqrt(z_factor)
        liver_mask = ((X - liver_cx)**2 / (r_x**2) + (Y - liver_cy)**2 / (r_y**2)) <= 1.0
        liver_data[:, :, z][liver_mask & body_mask] = 1
        ct_data[:, :, z][liver_mask & body_mask] = np.random.normal(60, 10, 
            np.sum(liver_mask & body_mask)).astype(np.int16)

# Save CT volume
ct_path = os.path.join(patient_dir, "liver_ct.nii.gz")
ct_img = nib.Nifti1Image(ct_data, affine)
nib.save(ct_img, ct_path)
print(f"Created CT volume: {ct_path}")

# Save liver segmentation as ground truth
seg_path = os.path.join(gt_dir, f"ircadb_patient{patient_num}_seg.nii.gz")
seg_img = nib.Nifti1Image(liver_data, affine)
nib.save(seg_img, seg_path)
print(f"Created liver segmentation: {seg_path}")

# Calculate and save original volume statistics
voxel_volume_ml = float(np.prod(spacing)) / 1000.0
liver_voxels = int(np.sum(liver_data > 0))
liver_volume_ml = liver_voxels * voxel_volume_ml

gt_stats = {
    "patient_num": patient_num,
    "original_liver_voxels": liver_voxels,
    "original_liver_volume_ml": liver_volume_ml,
    "voxel_volume_ml": voxel_volume_ml,
    "shape": list(liver_data.shape),
    "spacing_mm": list(spacing)
}

stats_path = os.path.join(gt_dir, f"scissors_task_original_stats.json")
with open(stats_path, 'w') as f:
    json.dump(gt_stats, f, indent=2)
print(f"Saved original stats: {stats_path}")
print(f"Original liver volume: {liver_volume_ml:.1f} mL ({liver_voxels} voxels)")
PYEOF
fi

echo "$PATIENT_NUM" > /tmp/ircadb_patient_num

# Record initial state
echo "Recording initial state..."
cat > /tmp/initial_segment_state.json << EOF
{
    "task_start_time": $(date +%s),
    "patient_num": "$PATIENT_NUM",
    "initial_segment_count": 1
}
EOF

# Create Slicer setup script
SETUP_SCRIPT="/tmp/setup_scissors_scene.py"
cat > "$SETUP_SCRIPT" << 'PYEOF'
import slicer
import os
import json

patient_num = os.environ.get("PATIENT_NUM", "5")
ircadb_dir = os.environ.get("IRCADB_DIR", "/home/ga/Documents/SlicerData/IRCADb")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
patient_dir = os.path.join(ircadb_dir, f"patient_{patient_num}")

print(f"Setting up scene for patient {patient_num}")
print(f"Patient directory: {patient_dir}")
print(f"Ground truth directory: {gt_dir}")

# Find CT volume
ct_file = None
for fname in os.listdir(patient_dir):
    if fname.endswith('.nii.gz') and 'seg' not in fname.lower():
        ct_file = os.path.join(patient_dir, fname)
        break

if ct_file and os.path.exists(ct_file):
    print(f"Loading CT: {ct_file}")
    volumeNode = slicer.util.loadVolume(ct_file)
    volumeNode.SetName("Liver_CT")
    
    # Set appropriate window/level for liver CT
    displayNode = volumeNode.GetDisplayNode()
    if displayNode:
        displayNode.SetAutoWindowLevel(False)
        displayNode.SetWindow(350)
        displayNode.SetLevel(50)
else:
    print("Warning: No CT volume found")
    volumeNode = None

# Load liver segmentation
seg_file = os.path.join(gt_dir, f"ircadb_patient{patient_num}_seg.nii.gz")
if os.path.exists(seg_file):
    print(f"Loading segmentation: {seg_file}")
    segmentationNode = slicer.util.loadSegmentation(seg_file)
    segmentationNode.SetName("LiverSegmentation")
    
    # Rename segment to Liver_Complete
    segmentation = segmentationNode.GetSegmentation()
    if segmentation.GetNumberOfSegments() > 0:
        segmentId = segmentation.GetNthSegmentID(0)
        segment = segmentation.GetSegment(segmentId)
        segment.SetName("Liver_Complete")
        segment.SetColor(0.85, 0.45, 0.35)  # Brownish-red for liver
        print(f"Renamed segment to: Liver_Complete")
    
    # Create 3D surface representation
    segmentationNode.CreateClosedSurfaceRepresentation()
    
    # Calculate and save original volume
    import SegmentStatistics
    segStatLogic = SegmentStatistics.SegmentStatisticsLogic()
    segStatLogic.getParameterNode().SetParameter("Segmentation", segmentationNode.GetID())
    if volumeNode:
        segStatLogic.getParameterNode().SetParameter("ScalarVolume", volumeNode.GetID())
    segStatLogic.computeStatistics()
    stats = segStatLogic.getStatistics()
    
    original_stats = {"segments": {}}
    for segId in stats.get("SegmentIDs", []):
        vol_key = f"{segId}.LabelmapSegmentStatisticsPlugin.volume_cm3"
        if vol_key in stats:
            seg = segmentation.GetSegment(segId)
            original_stats["segments"][segId] = {
                "name": seg.GetName() if seg else segId,
                "volume_cm3": stats[vol_key]
            }
            print(f"Original volume: {stats[vol_key]:.2f} cm³")
    
    # Save for verification
    stats_file = os.path.join(gt_dir, "scissors_task_original_stats.json")
    # Merge with existing stats if present
    if os.path.exists(stats_file):
        with open(stats_file, 'r') as f:
            existing = json.load(f)
        existing.update(original_stats)
        original_stats = existing
    
    with open(stats_file, 'w') as f:
        json.dump(original_stats, f, indent=2)
else:
    print(f"Warning: Segmentation not found at {seg_file}")

# Set up layout
layoutManager = slicer.app.layoutManager()
layoutManager.setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutFourUpView)

# Switch to Segment Editor
slicer.util.selectModule('SegmentEditor')

# Configure Segment Editor
segEditorWidget = slicer.modules.segmenteditor.widgetRepresentation().self()
if 'segmentationNode' in dir():
    segEditorWidget.setSegmentationNode(segmentationNode)
if volumeNode:
    segEditorWidget.setSourceVolumeNode(volumeNode)

# Reset 3D view
threeDWidget = layoutManager.threeDWidget(0)
if threeDWidget:
    threeDView = threeDWidget.threeDView()
    threeDView.resetFocalPoint()
    threeDView.resetCamera()

print("Scene setup complete - ready for scissors task")
PYEOF

chmod 644 "$SETUP_SCRIPT"

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 3

# Launch Slicer with setup script
echo "Launching 3D Slicer..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script "$SETUP_SCRIPT" > /tmp/slicer_setup.log 2>&1 &

# Wait for Slicer to start
echo "Waiting for Slicer to start..."
wait_for_slicer 120

# Additional wait for scene to load
sleep 15

# Maximize and focus window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial state screenshot..."
take_screenshot /tmp/task_initial_state.png ga

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "Warning: Could not capture initial screenshot"
fi

echo ""
echo "=== Scissors Task Setup Complete ==="
echo "Patient: $PATIENT_NUM"
echo "Data directory: $PATIENT_DIR"
echo ""
echo "TASK: Use the Scissors effect to split 'Liver_Complete' into two segments."
echo "      Each segment should be 25-75% of the original volume."