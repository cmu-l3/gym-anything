#!/bin/bash
echo "=== Setting up Portal Vein Bifurcation Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_NUM="${IRCADB_PATIENT:-5}"

mkdir -p "$IRCADB_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Record initial state - check if output fiducial exists
OUTPUT_FIDUCIAL="$IRCADB_DIR/portal_bifurcation.mrk.json"
if [ -f "$OUTPUT_FIDUCIAL" ]; then
    INITIAL_FIDUCIAL_EXISTS="true"
    INITIAL_FIDUCIAL_MTIME=$(stat -c%Y "$OUTPUT_FIDUCIAL" 2>/dev/null || echo "0")
else
    INITIAL_FIDUCIAL_EXISTS="false"
    INITIAL_FIDUCIAL_MTIME="0"
fi

cat > /tmp/initial_state.json << EOF
{
    "fiducial_exists": $INITIAL_FIDUCIAL_EXISTS,
    "fiducial_mtime": $INITIAL_FIDUCIAL_MTIME,
    "task_start_time": $(date +%s),
    "patient_num": "$PATIENT_NUM"
}
EOF

echo "Initial state recorded"

# Prepare IRCADb data
echo "Preparing IRCADb liver CT data..."
export PATIENT_NUM IRCADB_DIR GROUND_TRUTH_DIR

/workspace/scripts/prepare_ircadb_data.sh "$PATIENT_NUM" || {
    echo "WARNING: prepare_ircadb_data.sh returned non-zero, checking if data exists..."
}

# Verify data directory exists
TARGET_DIR="$IRCADB_DIR/patient_${PATIENT_NUM}"
if [ ! -d "$TARGET_DIR" ]; then
    echo "ERROR: IRCADb data not found at $TARGET_DIR"
    echo "Attempting to generate synthetic data..."
    
    # Generate minimal synthetic data for testing
    python3 << 'PYEOF'
import os
import json
import numpy as np

try:
    import nibabel as nib
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

ircadb_dir = os.environ.get("IRCADB_DIR", "/home/ga/Documents/SlicerData/IRCADb")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
patient_num = os.environ.get("PATIENT_NUM", "5")

target_dir = os.path.join(ircadb_dir, f"patient_{patient_num}")
os.makedirs(target_dir, exist_ok=True)

# Create synthetic abdominal CT
nx, ny, nz = 256, 256, 100
spacing = (0.78, 0.78, 2.5)

np.random.seed(42)
ct_data = np.random.normal(40, 15, (nx, ny, nz)).astype(np.int16)

# Create body outline
Y, X = np.ogrid[:nx, :ny]
cx, cy = nx // 2, ny // 2
body_mask = ((X - cx)**2 / (100**2) + (Y - cy)**2 / (80**2)) <= 1.0

for z in range(nz):
    ct_data[:, :, z][~body_mask] = -1000

# Create portal vein (bright tubular structure)
pv_cx, pv_cy = cx, cy + 25
pv_radius = 8

for z in range(30, 70):
    # Make it bifurcate around z=50
    if z < 50:
        pv_mask = ((X - pv_cx)**2 + (Y - pv_cy)**2) <= pv_radius**2
        ct_data[:, :, z][pv_mask & body_mask] = np.random.normal(180, 20, np.sum(pv_mask & body_mask)).astype(np.int16)
    else:
        # Left branch
        left_cx = pv_cx - (z - 50) * 0.5
        left_mask = ((X - left_cx)**2 + (Y - pv_cy)**2) <= (pv_radius * 0.7)**2
        ct_data[:, :, z][left_mask & body_mask] = np.random.normal(175, 20, np.sum(left_mask & body_mask)).astype(np.int16)
        
        # Right branch
        right_cx = pv_cx + (z - 50) * 0.5
        right_mask = ((X - right_cx)**2 + (Y - pv_cy)**2) <= (pv_radius * 0.7)**2
        ct_data[:, :, z][right_mask & body_mask] = np.random.normal(175, 20, np.sum(right_mask & body_mask)).astype(np.int16)

# Create affine
affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

# Save CT
ct_img = nib.Nifti1Image(ct_data, affine)
ct_path = os.path.join(target_dir, "ct_volume.nii.gz")
nib.save(ct_img, ct_path)
print(f"Saved synthetic CT to {ct_path}")

# Save ground truth bifurcation point
bifurcation_voxel = [pv_cx, pv_cy, 50]  # z=50 is bifurcation level
bifurcation_ras = [
    bifurcation_voxel[0] * spacing[0],
    bifurcation_voxel[1] * spacing[1],
    bifurcation_voxel[2] * spacing[2]
]

gt_data = {
    "patient_num": patient_num,
    "bifurcation_voxel_ijk": bifurcation_voxel,
    "bifurcation_ras": bifurcation_ras,
    "tolerance_mm": 8.0,
    "acceptable_tolerance_mm": 15.0,
    "description": "Portal vein bifurcation (synthetic data)"
}

gt_path = os.path.join(gt_dir, f"ircadb_patient{patient_num}_portal_bifurcation.json")
with open(gt_path, 'w') as f:
    json.dump(gt_data, f, indent=2)
print(f"Saved ground truth to {gt_path}")
PYEOF
fi

# Save patient number for export script
echo "$PATIENT_NUM" > /tmp/ircadb_patient_num

# Compute portal vein bifurcation ground truth if not exists
GT_FILE="$GROUND_TRUTH_DIR/ircadb_patient${PATIENT_NUM}_portal_bifurcation.json"

if [ ! -f "$GT_FILE" ]; then
    echo "Computing portal vein bifurcation ground truth..."
    python3 << 'PYEOF'
import os
import json
import numpy as np

patient_num = os.environ.get("PATIENT_NUM", "5")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
ircadb_dir = os.environ.get("IRCADB_DIR", "/home/ga/Documents/SlicerData/IRCADb")

seg_path = os.path.join(gt_dir, f"ircadb_patient{patient_num}_seg.nii.gz")
output_path = os.path.join(gt_dir, f"ircadb_patient{patient_num}_portal_bifurcation.json")

# Default fallback location (hepatic hilum approximation)
default_bifurcation = {
    "patient_num": patient_num,
    "bifurcation_ras": [0.0, -30.0, 60.0],
    "tolerance_mm": 10.0,
    "acceptable_tolerance_mm": 20.0,
    "description": "Approximate portal vein bifurcation (default)"
}

try:
    import nibabel as nib
    from scipy.ndimage import label as scipy_label
    
    if not os.path.exists(seg_path):
        print(f"Segmentation not found at {seg_path}, using default")
        with open(output_path, 'w') as f:
            json.dump(default_bifurcation, f, indent=2)
    else:
        seg = nib.load(seg_path)
        data = seg.get_fdata().astype(np.int32)
        affine = seg.affine
        spacing = seg.header.get_zooms()[:3]
        
        # Portal vein is typically label 3
        portal_mask = (data == 3)
        
        if not np.any(portal_mask):
            print("No portal vein segmentation found, using liver centroid")
            liver_mask = (data == 1) | (data == 2)
            if np.any(liver_mask):
                coords = np.argwhere(liver_mask)
                centroid = coords.mean(axis=0)
                # Portal vein bifurcation is typically posterior-superior in liver hilum
                centroid[1] += 15  # More posterior
                centroid[2] += 5   # Slightly superior
                bifurcation_voxel = centroid
            else:
                bifurcation_voxel = np.array(data.shape) / 2
        else:
            coords = np.argwhere(portal_mask)
            centroid = coords.mean(axis=0)
            
            # Find bifurcation level - where vessel splits
            z_coords = coords[:, 2]
            z_75th = np.percentile(z_coords, 70)
            
            bifurcation_voxel = centroid.copy()
            
            # Look for actual split point
            for z in range(int(z_75th), int(z_coords.max())):
                slice_mask = portal_mask[:, :, z]
                if np.sum(slice_mask) > 0:
                    labeled, n = scipy_label(slice_mask)
                    if n >= 2:
                        # Found split - this is bifurcation level
                        slice_coords = np.argwhere(slice_mask)
                        bifurcation_voxel = np.array([
                            slice_coords[:, 0].mean(),
                            slice_coords[:, 1].mean(),
                            z
                        ])
                        print(f"Found bifurcation at slice z={z}")
                        break
        
        # Convert to RAS coordinates
        voxel_h = np.append(bifurcation_voxel, 1)
        ras_coords = affine.dot(voxel_h)[:3]
        
        result = {
            "patient_num": patient_num,
            "bifurcation_voxel_ijk": [float(x) for x in bifurcation_voxel],
            "bifurcation_ras": [float(x) for x in ras_coords],
            "tolerance_mm": 8.0,
            "acceptable_tolerance_mm": 15.0,
            "description": "Portal vein bifurcation point"
        }
        
        with open(output_path, 'w') as f:
            json.dump(result, f, indent=2)
        
        print(f"Portal bifurcation saved to {output_path}")
        print(f"  RAS coordinates: {ras_coords}")

except Exception as e:
    print(f"Error computing bifurcation: {e}")
    import traceback
    traceback.print_exc()
    with open(output_path, 'w') as f:
        json.dump(default_bifurcation, f, indent=2)
PYEOF
fi

# Clean previous task outputs
rm -f "$OUTPUT_FIDUCIAL" 2>/dev/null || true
rm -f /tmp/portal_task_result.json 2>/dev/null || true

# Find CT data file
CT_FILE=""
TARGET_DIR="$IRCADB_DIR/patient_${PATIENT_NUM}"

if [ -f "$TARGET_DIR/ct_volume.nii.gz" ]; then
    CT_FILE="$TARGET_DIR/ct_volume.nii.gz"
elif [ -d "$TARGET_DIR/PATIENT_DICOM" ]; then
    CT_FILE="$TARGET_DIR/PATIENT_DICOM"
fi

echo "CT data: $CT_FILE"

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with CT data
echo "Launching 3D Slicer with liver CT..."
if [ -n "$CT_FILE" ] && [ -e "$CT_FILE" ]; then
    su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$CT_FILE' > /tmp/slicer_launch.log 2>&1 &"
else
    echo "WARNING: No CT file found, launching Slicer without data"
    su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer > /tmp/slicer_launch.log 2>&1 &"
fi

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
for i in {1..90}; do
    if pgrep -f "Slicer" > /dev/null 2>&1; then
        SLICER_WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "slicer" | head -1 | awk '{print $1}')
        if [ -n "$SLICER_WID" ]; then
            echo "3D Slicer window detected after ${i}s"
            break
        fi
    fi
    sleep 1
done

# Wait additional time for data to load
sleep 10

# Maximize and focus window
SLICER_WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "slicer" | head -1 | awk '{print $1}')
if [ -n "$SLICER_WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$SLICER_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$SLICER_WID" 2>/dev/null || true
fi

sleep 3

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

# Verify screenshot was captured
if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo "Patient: $PATIENT_NUM"
echo "Data directory: $TARGET_DIR"
echo "Ground truth: $GT_FILE"
echo ""
echo "TASK: Locate the portal vein bifurcation and place a fiducial marker"
echo "      named 'PortalBifurcation' at that location."
echo ""
echo "Save fiducial to: $IRCADB_DIR/portal_bifurcation.mrk.json"