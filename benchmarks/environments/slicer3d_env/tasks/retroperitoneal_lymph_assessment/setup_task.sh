#!/bin/bash
echo "=== Setting up Retroperitoneal Lymph Node Assessment Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Prepare AMOS data (downloads real data if not exists)
echo "Preparing AMOS 2022 data..."
export CASE_ID GROUND_TRUTH_DIR
/workspace/scripts/prepare_amos_data.sh "$CASE_ID"

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
fi

CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"

echo "Using case: $CASE_ID"

# Verify CT file exists
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT volume not found at $CT_FILE"
    exit 1
fi
echo "CT volume found: $CT_FILE"

# Create synthetic lymph nodes and ground truth
echo "Adding synthetic lymph nodes for assessment task..."
python3 << 'PYEOF'
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

case_id = os.environ.get("CASE_ID", "amos_0001")
amos_dir = os.environ.get("AMOS_DIR", "/home/ga/Documents/SlicerData/AMOS")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")

ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")
output_ct_path = os.path.join(amos_dir, f"{case_id}_with_nodes.nii.gz")
gt_nodes_path = os.path.join(gt_dir, f"{case_id}_lymph_nodes_gt.json")

print(f"Loading CT: {ct_path}")
ct_nii = nib.load(ct_path)
ct_data = ct_nii.get_fdata().astype(np.float32)
spacing = ct_nii.header.get_zooms()[:3]

print(f"CT shape: {ct_data.shape}, spacing: {spacing}")

np.random.seed(42)

# Get approximate center and dimensions
nx, ny, nz = ct_data.shape
center_x, center_y = nx // 2, ny // 2

# Find approximate location of aorta (high-density tubular structure near center-posterior)
# For synthetic data, we estimate based on typical anatomy
aorta_x = center_x
aorta_y = center_y + int(25 / spacing[1])  # Posterior to center

# Define lymph node locations relative to major vessels
# Stations: para-aortic (lateral to aorta), paracaval (lateral to IVC), aortocaval (between)
lymph_nodes = []

# Node 1: Para-aortic LEFT - ENLARGED (14mm)
node1 = {
    "id": 1,
    "station": "para-aortic-left",
    "center_voxel": [aorta_x - int(20/spacing[0]), aorta_y, int(nz * 0.45)],
    "short_axis_mm": 14.0,
    "long_axis_mm": 18.0,
    "classification": "enlarged",
    "hu_value": 45
}
lymph_nodes.append(node1)

# Node 2: Para-aortic RIGHT - Normal (7mm)
node2 = {
    "id": 2,
    "station": "para-aortic-right",
    "center_voxel": [aorta_x + int(18/spacing[0]), aorta_y - int(5/spacing[1]), int(nz * 0.50)],
    "short_axis_mm": 7.0,
    "long_axis_mm": 10.0,
    "classification": "normal",
    "hu_value": 40
}
lymph_nodes.append(node2)

# Node 3: Aortocaval - ENLARGED (16mm) - this is the largest
node3 = {
    "id": 3,
    "station": "aortocaval",
    "center_voxel": [aorta_x + int(8/spacing[0]), aorta_y + int(3/spacing[1]), int(nz * 0.48)],
    "short_axis_mm": 16.0,
    "long_axis_mm": 22.0,
    "classification": "enlarged",
    "hu_value": 48
}
lymph_nodes.append(node3)

# Node 4: Paracaval - Normal (6mm)
node4 = {
    "id": 4,
    "station": "paracaval",
    "center_voxel": [aorta_x + int(25/spacing[0]), aorta_y - int(8/spacing[1]), int(nz * 0.52)],
    "short_axis_mm": 6.0,
    "long_axis_mm": 9.0,
    "classification": "normal",
    "hu_value": 38
}
lymph_nodes.append(node4)

# Node 5: Retroaortic - ENLARGED (12mm)
node5 = {
    "id": 5,
    "station": "retroaortic",
    "center_voxel": [aorta_x - int(5/spacing[0]), aorta_y + int(15/spacing[1]), int(nz * 0.42)],
    "short_axis_mm": 12.0,
    "long_axis_mm": 15.0,
    "classification": "enlarged",
    "hu_value": 42
}
lymph_nodes.append(node5)

# Node 6: Para-aortic LEFT lower - Normal (8mm)
node6 = {
    "id": 6,
    "station": "para-aortic-left",
    "center_voxel": [aorta_x - int(22/spacing[0]), aorta_y + int(2/spacing[1]), int(nz * 0.35)],
    "short_axis_mm": 8.0,
    "long_axis_mm": 11.0,
    "classification": "normal",
    "hu_value": 43
}
lymph_nodes.append(node6)

print(f"Creating {len(lymph_nodes)} synthetic lymph nodes...")

# Add lymph nodes to CT data
modified_ct = ct_data.copy()

for node in lymph_nodes:
    cx, cy, cz = node["center_voxel"]
    
    # Ensure coordinates are within bounds
    cx = int(np.clip(cx, 20, nx - 20))
    cy = int(np.clip(cy, 20, ny - 20))
    cz = int(np.clip(cz, 10, nz - 10))
    node["center_voxel"] = [cx, cy, cz]
    
    # Calculate radii in voxels (ellipsoid)
    short_radius = node["short_axis_mm"] / 2.0
    long_radius = node["long_axis_mm"] / 2.0
    
    rx = int(np.ceil(short_radius / spacing[0]))
    ry = int(np.ceil(short_radius / spacing[1]))
    rz = int(np.ceil(long_radius / spacing[2]))  # Long axis along z
    
    # Create ellipsoid lymph node
    hu = node["hu_value"]
    for dx in range(-rx-1, rx+2):
        for dy in range(-ry-1, ry+2):
            for dz in range(-rz-1, rz+2):
                x, y, z = cx + dx, cy + dy, cz + dz
                if 0 <= x < nx and 0 <= y < ny and 0 <= z < nz:
                    # Ellipsoid equation
                    dist = (dx * spacing[0] / short_radius)**2 + \
                           (dy * spacing[1] / short_radius)**2 + \
                           (dz * spacing[2] / long_radius)**2
                    if dist <= 1.0:
                        # Add some texture variation
                        noise = np.random.normal(0, 5)
                        modified_ct[x, y, z] = hu + noise
    
    # Convert voxel coords to physical coords (mm)
    physical_center = [
        float(cx * spacing[0]),
        float(cy * spacing[1]),
        float(cz * spacing[2])
    ]
    node["center_mm"] = physical_center
    
    print(f"  Node {node['id']}: {node['station']}, {node['short_axis_mm']}mm ({node['classification']}) at z={cz}")

# Save modified CT
print(f"Saving modified CT to {output_ct_path}")
modified_nii = nib.Nifti1Image(modified_ct.astype(np.int16), ct_nii.affine, ct_nii.header)
nib.save(modified_nii, output_ct_path)

# Calculate ground truth summary
enlarged_nodes = [n for n in lymph_nodes if n["classification"] == "enlarged"]
normal_nodes = [n for n in lymph_nodes if n["classification"] == "normal"]
largest_node = max(lymph_nodes, key=lambda x: x["short_axis_mm"])

gt_summary = {
    "case_id": case_id,
    "total_nodes": len(lymph_nodes),
    "enlarged_nodes_count": len(enlarged_nodes),
    "normal_nodes_count": len(normal_nodes),
    "largest_node_mm": largest_node["short_axis_mm"],
    "largest_node_station": largest_node["station"],
    "largest_node_id": largest_node["id"],
    "n_stage": "N+" if len(enlarged_nodes) > 0 else "N0",
    "voxel_spacing_mm": [float(s) for s in spacing],
    "nodes": lymph_nodes
}

# Save ground truth
os.makedirs(gt_dir, exist_ok=True)
with open(gt_nodes_path, 'w') as f:
    json.dump(gt_summary, f, indent=2)

print(f"\nGround truth saved to {gt_nodes_path}")
print(f"Summary: {len(lymph_nodes)} nodes ({len(enlarged_nodes)} enlarged, {len(normal_nodes)} normal)")
print(f"Largest node: {largest_node['short_axis_mm']}mm at {largest_node['station']}")
print(f"N-stage: {gt_summary['n_stage']}")
PYEOF

# Use the modified CT with lymph nodes
CT_WITH_NODES="$AMOS_DIR/${CASE_ID}_with_nodes.nii.gz"
if [ -f "$CT_WITH_NODES" ]; then
    CT_FILE="$CT_WITH_NODES"
    echo "Using CT with synthetic lymph nodes: $CT_FILE"
fi

# Record initial state
rm -f /tmp/lymph_task_result.json 2>/dev/null || true
rm -f "$AMOS_DIR/lymph_nodes.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/lymph_node_report.json" 2>/dev/null || true
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_iso.txt

# Create Slicer Python script to load CT
cat > /tmp/load_lymph_ct.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
case_id = "$CASE_ID"

print(f"Loading abdominal CT for lymph node assessment: {case_id}")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")
    
    # Set soft tissue window for lymph node visualization
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Soft tissue window - optimal for lymph nodes
        displayNode.SetWindow(350)
        displayNode.SetLevel(50)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Position to retroperitoneal region (middle of volume, axial view)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    # Center on retroperitoneal region
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        if color == "Red":  # Axial
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":  # Coronal
            sliceNode.SetSliceOffset(center[1])
        else:  # Sagittal
            sliceNode.SetSliceOffset(center[0])
    
    print(f"CT loaded with soft tissue window (W=350, L=50)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for lymph node assessment")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_lymph_ct.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 10

# Configure window
echo "Configuring Slicer window..."
sleep 3

WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    focus_window "$WID"
    
    # Maximize
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 5

# Take initial screenshot
take_screenshot /tmp/lymph_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Retroperitoneal Lymphadenopathy Assessment"
echo "================================================="
echo ""
echo "You are evaluating a patient for lymphadenopathy."
echo ""
echo "Instructions:"
echo "  1. Navigate through the retroperitoneum (renal hilum to aortic bifurcation)"
echo "  2. Identify lymph nodes in standard stations:"
echo "     - Para-aortic (lateral to aorta)"
echo "     - Paracaval (lateral to IVC)"
echo "     - Aortocaval (between aorta and IVC)"
echo "  3. Measure the SHORT-AXIS diameter of each node"
echo "  4. Classify: Normal (<10mm) vs Enlarged (>=10mm)"
echo ""
echo "Save outputs:"
echo "  - Markups: ~/Documents/SlicerData/AMOS/lymph_nodes.mrk.json"
echo "  - Report: ~/Documents/SlicerData/AMOS/lymph_node_report.json"
echo ""