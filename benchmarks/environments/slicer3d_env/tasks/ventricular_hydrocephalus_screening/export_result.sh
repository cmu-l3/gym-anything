#!/bin/bash
echo "=== Exporting Ventricular Assessment Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
GT_DIR="/var/lib/slicer/ground_truth"
RESULT_FILE="/tmp/ventricle_task_result.json"

# Get task timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot "$SAMPLE_DIR/Screenshots/final_state.png" 2>/dev/null || \
    DISPLAY=:1 import -window root "$SAMPLE_DIR/Screenshots/final_state.png" 2>/dev/null || true

if [ -f "$SAMPLE_DIR/Screenshots/final_state.png" ]; then
    cp "$SAMPLE_DIR/Screenshots/final_state.png" /tmp/task_final.png 2>/dev/null || true
    echo "Final screenshot captured"
fi

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
fi

# ================================================================
# CHECK SEGMENTATION FILE
# ================================================================
SEGMENTATION_EXISTS="false"
SEGMENTATION_PATH=""
SEGMENTATION_SIZE=0
SEGMENTATION_VOLUME_ML=0
SEGMENTATION_CREATED_DURING_TASK="false"
CENTROID_NORMALIZED=""

POSSIBLE_SEG_PATHS=(
    "$SAMPLE_DIR/ventricle_segmentation.nii.gz"
    "$SAMPLE_DIR/ventricle_segmentation.nii"
    "$SAMPLE_DIR/Segmentation.nii.gz"
    "$SAMPLE_DIR/segmentation.nii.gz"
    "$SAMPLE_DIR/LateralVentricles.nii.gz"
    "/home/ga/Documents/ventricle_segmentation.nii.gz"
    "/home/ga/ventricle_segmentation.nii.gz"
)

for path in "${POSSIBLE_SEG_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SEGMENTATION_EXISTS="true"
        SEGMENTATION_PATH="$path"
        SEGMENTATION_SIZE=$(stat -c%s "$path" 2>/dev/null || echo 0)
        SEG_MTIME=$(stat -c%Y "$path" 2>/dev/null || echo 0)
        
        if [ "$SEG_MTIME" -gt "$TASK_START" ]; then
            SEGMENTATION_CREATED_DURING_TASK="true"
        fi
        
        echo "Found segmentation at: $path (${SEGMENTATION_SIZE} bytes)"
        
        # Copy to expected location if needed
        if [ "$path" != "$SAMPLE_DIR/ventricle_segmentation.nii.gz" ]; then
            cp "$path" "$SAMPLE_DIR/ventricle_segmentation.nii.gz" 2>/dev/null || true
        fi
        break
    fi
done

# Analyze segmentation if it exists
if [ "$SEGMENTATION_EXISTS" = "true" ]; then
    echo "Analyzing segmentation..."
    python3 << 'PYEOF'
import os
import json
import numpy as np

seg_path = os.environ.get("SEGMENTATION_PATH", "")
if not seg_path:
    for p in ["/home/ga/Documents/SlicerData/SampleData/ventricle_segmentation.nii.gz",
              "/home/ga/Documents/SlicerData/SampleData/ventricle_segmentation.nii"]:
        if os.path.exists(p):
            seg_path = p
            break

if not seg_path or not os.path.exists(seg_path):
    print("Segmentation not found for analysis")
    exit(0)

try:
    import nibabel as nib
except ImportError:
    import subprocess
    import sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

try:
    seg = nib.load(seg_path)
    data = seg.get_fdata()
    voxel_dims = seg.header.get_zooms()[:3]
    voxel_volume_mm3 = float(np.prod(voxel_dims))
    
    # Count non-zero voxels
    nonzero_count = int(np.sum(data > 0))
    total_volume_mm3 = nonzero_count * voxel_volume_mm3
    total_volume_ml = total_volume_mm3 / 1000.0
    
    # Calculate centroid (normalized to volume dimensions)
    if nonzero_count > 0:
        indices = np.argwhere(data > 0)
        centroid = indices.mean(axis=0)
        centroid_normalized = (centroid / np.array(data.shape)).tolist()
    else:
        centroid_normalized = [0, 0, 0]
    
    result = {
        "volume_ml": round(total_volume_ml, 2),
        "voxel_count": nonzero_count,
        "voxel_volume_mm3": round(voxel_volume_mm3, 4),
        "centroid_normalized": [round(c, 3) for c in centroid_normalized],
        "data_shape": list(data.shape)
    }
    
    with open("/tmp/seg_analysis.json", "w") as f:
        json.dump(result, f)
    
    print(f"Segmentation volume: {total_volume_ml:.2f} mL")
    print(f"Voxel count: {nonzero_count}")
    print(f"Centroid (normalized): {centroid_normalized}")
        
except Exception as e:
    print(f"Error analyzing segmentation: {e}")
PYEOF
    
    # Read analysis results
    if [ -f "/tmp/seg_analysis.json" ]; then
        SEGMENTATION_VOLUME_ML=$(python3 -c "import json; print(json.load(open('/tmp/seg_analysis.json'))['volume_ml'])" 2>/dev/null || echo "0")
        CENTROID_NORMALIZED=$(python3 -c "import json; print(json.dumps(json.load(open('/tmp/seg_analysis.json'))['centroid_normalized']))" 2>/dev/null || echo "[]")
    fi
fi

# ================================================================
# CHECK RULER MARKUPS
# ================================================================
FRONTAL_RULER_EXISTS="false"
FRONTAL_RULER_PATH=""
FRONTAL_WIDTH=0

POSSIBLE_FRONTAL_PATHS=(
    "$SAMPLE_DIR/frontal_horn_ruler.mrk.json"
    "$SAMPLE_DIR/frontal_horn.mrk.json"
    "$SAMPLE_DIR/FrontalHorn.mrk.json"
    "$SAMPLE_DIR/frontal_ruler.mrk.json"
)

for path in "${POSSIBLE_FRONTAL_PATHS[@]}"; do
    if [ -f "$path" ]; then
        FRONTAL_RULER_EXISTS="true"
        FRONTAL_RULER_PATH="$path"
        echo "Found frontal horn ruler at: $path"
        
        if [ "$path" != "$SAMPLE_DIR/frontal_horn_ruler.mrk.json" ]; then
            cp "$path" "$SAMPLE_DIR/frontal_horn_ruler.mrk.json" 2>/dev/null || true
        fi
        break
    fi
done

# Also check for any line markups saved by Slicer
if [ "$FRONTAL_RULER_EXISTS" = "false" ]; then
    for f in "$SAMPLE_DIR"/*.mrk.json; do
        if [ -f "$f" ] && grep -qi "frontal\|horn" "$f" 2>/dev/null; then
            FRONTAL_RULER_EXISTS="true"
            FRONTAL_RULER_PATH="$f"
            cp "$f" "$SAMPLE_DIR/frontal_horn_ruler.mrk.json" 2>/dev/null || true
            echo "Found frontal ruler in: $f"
            break
        fi
    done
fi

SKULL_RULER_EXISTS="false"
SKULL_RULER_PATH=""
SKULL_DIAMETER=0

POSSIBLE_SKULL_PATHS=(
    "$SAMPLE_DIR/skull_diameter_ruler.mrk.json"
    "$SAMPLE_DIR/skull_diameter.mrk.json"
    "$SAMPLE_DIR/SkullDiameter.mrk.json"
    "$SAMPLE_DIR/skull_ruler.mrk.json"
    "$SAMPLE_DIR/internal_diameter.mrk.json"
)

for path in "${POSSIBLE_SKULL_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SKULL_RULER_EXISTS="true"
        SKULL_RULER_PATH="$path"
        echo "Found skull diameter ruler at: $path"
        
        if [ "$path" != "$SAMPLE_DIR/skull_diameter_ruler.mrk.json" ]; then
            cp "$path" "$SAMPLE_DIR/skull_diameter_ruler.mrk.json" 2>/dev/null || true
        fi
        break
    fi
done

# Also check for any line markups saved by Slicer
if [ "$SKULL_RULER_EXISTS" = "false" ]; then
    for f in "$SAMPLE_DIR"/*.mrk.json; do
        if [ -f "$f" ] && grep -qi "skull\|diameter\|internal" "$f" 2>/dev/null; then
            SKULL_RULER_EXISTS="true"
            SKULL_RULER_PATH="$f"
            cp "$f" "$SAMPLE_DIR/skull_diameter_ruler.mrk.json" 2>/dev/null || true
            echo "Found skull ruler in: $f"
            break
        fi
    done
fi

# Extract measurements from ruler files
extract_ruler_measurement() {
    local file="$1"
    python3 << PYEOF
import json
import math
try:
    with open("$file") as f:
        data = json.load(f)
    
    # Slicer markup format can vary
    if 'markups' in data:
        for m in data['markups']:
            # Check for measurements array
            if 'measurements' in m:
                for meas in m['measurements']:
                    if 'value' in meas and meas.get('enabled', True):
                        print(round(meas['value'], 2))
                        exit(0)
            
            # Calculate from control points
            if 'controlPoints' in m and len(m['controlPoints']) >= 2:
                p1 = m['controlPoints'][0].get('position', [0,0,0])
                p2 = m['controlPoints'][1].get('position', [0,0,0])
                dist = math.sqrt(sum((a-b)**2 for a,b in zip(p1,p2)))
                print(round(dist, 2))
                exit(0)
    
    # Old format
    if 'control_points' in data and len(data['control_points']) >= 2:
        p1 = data['control_points'][0]
        p2 = data['control_points'][1]
        dist = math.sqrt(sum((a-b)**2 for a,b in zip(p1,p2)))
        print(round(dist, 2))
        exit(0)
        
    print(0)
except Exception as e:
    print(0)
PYEOF
}

if [ "$FRONTAL_RULER_EXISTS" = "true" ] && [ -f "$SAMPLE_DIR/frontal_horn_ruler.mrk.json" ]; then
    FRONTAL_WIDTH=$(extract_ruler_measurement "$SAMPLE_DIR/frontal_horn_ruler.mrk.json")
    echo "Frontal horn width: $FRONTAL_WIDTH mm"
fi

if [ "$SKULL_RULER_EXISTS" = "true" ] && [ -f "$SAMPLE_DIR/skull_diameter_ruler.mrk.json" ]; then
    SKULL_DIAMETER=$(extract_ruler_measurement "$SAMPLE_DIR/skull_diameter_ruler.mrk.json")
    echo "Skull diameter: $SKULL_DIAMETER mm"
fi

# Calculate Evans' Index
EVANS_INDEX=0
if [ "$FRONTAL_WIDTH" != "0" ] && [ "$SKULL_DIAMETER" != "0" ]; then
    EVANS_INDEX=$(python3 -c "print(round($FRONTAL_WIDTH / $SKULL_DIAMETER, 3))" 2>/dev/null || echo "0")
    echo "Calculated Evans' Index: $EVANS_INDEX"
fi

# ================================================================
# CHECK REPORT FILE
# ================================================================
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_VOLUME=""
REPORTED_CLASSIFICATION=""
REPORTED_EVANS=""

POSSIBLE_REPORT_PATHS=(
    "$SAMPLE_DIR/ventricle_report.json"
    "$SAMPLE_DIR/report.json"
    "$SAMPLE_DIR/ventricle_report.txt"
    "/home/ga/Documents/ventricle_report.json"
    "/home/ga/ventricle_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        
        if [ "$path" != "$SAMPLE_DIR/ventricle_report.json" ]; then
            cp "$path" "$SAMPLE_DIR/ventricle_report.json" 2>/dev/null || true
        fi
        
        # Extract report fields
        if [[ "$path" == *.json ]]; then
            REPORTED_VOLUME=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('ventricular_volume_ml', d.get('volume_ml', d.get('volume', ''))))" 2>/dev/null || echo "")
            REPORTED_CLASSIFICATION=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('classification', ''))" 2>/dev/null || echo "")
            REPORTED_EVANS=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('evans_index', ''))" 2>/dev/null || echo "")
        fi
        break
    fi
done

echo "Report values: volume=$REPORTED_VOLUME, classification=$REPORTED_CLASSIFICATION, evans=$REPORTED_EVANS"

# ================================================================
# COPY FILES FOR VERIFIER
# ================================================================
echo "Preparing files for verification..."

# Copy segmentation
if [ -f "$SAMPLE_DIR/ventricle_segmentation.nii.gz" ]; then
    cp "$SAMPLE_DIR/ventricle_segmentation.nii.gz" /tmp/agent_segmentation.nii.gz 2>/dev/null || true
    chmod 644 /tmp/agent_segmentation.nii.gz 2>/dev/null || true
fi

# Copy ruler files
if [ -f "$SAMPLE_DIR/frontal_horn_ruler.mrk.json" ]; then
    cp "$SAMPLE_DIR/frontal_horn_ruler.mrk.json" /tmp/frontal_horn_ruler.mrk.json 2>/dev/null || true
    chmod 644 /tmp/frontal_horn_ruler.mrk.json 2>/dev/null || true
fi

if [ -f "$SAMPLE_DIR/skull_diameter_ruler.mrk.json" ]; then
    cp "$SAMPLE_DIR/skull_diameter_ruler.mrk.json" /tmp/skull_diameter_ruler.mrk.json 2>/dev/null || true
    chmod 644 /tmp/skull_diameter_ruler.mrk.json 2>/dev/null || true
fi

# Copy report
if [ -f "$SAMPLE_DIR/ventricle_report.json" ]; then
    cp "$SAMPLE_DIR/ventricle_report.json" /tmp/agent_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_report.json 2>/dev/null || true
fi

# Copy ground truth for verifier
if [ -f "$GT_DIR/mrhead_ventricle_gt.json" ]; then
    cp "$GT_DIR/mrhead_ventricle_gt.json" /tmp/ground_truth.json 2>/dev/null || true
    chmod 644 /tmp/ground_truth.json 2>/dev/null || true
fi

# ================================================================
# CREATE RESULT JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "slicer_running": $SLICER_RUNNING,
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    
    "segmentation_exists": $SEGMENTATION_EXISTS,
    "segmentation_path": "$SEGMENTATION_PATH",
    "segmentation_size_bytes": $SEGMENTATION_SIZE,
    "segmentation_created_during_task": $SEGMENTATION_CREATED_DURING_TASK,
    "segmentation_volume_ml": $SEGMENTATION_VOLUME_ML,
    "segmentation_centroid_normalized": $CENTROID_NORMALIZED,
    
    "frontal_ruler_exists": $FRONTAL_RULER_EXISTS,
    "frontal_ruler_path": "$FRONTAL_RULER_PATH",
    "frontal_horn_width_mm": $FRONTAL_WIDTH,
    
    "skull_ruler_exists": $SKULL_RULER_EXISTS,
    "skull_ruler_path": "$SKULL_RULER_PATH",
    "skull_diameter_mm": $SKULL_DIAMETER,
    
    "evans_index_calculated": $EVANS_INDEX,
    
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "reported_volume_ml": "$REPORTED_VOLUME",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "reported_evans_index": "$REPORTED_EVANS",
    
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Validate JSON and fix if needed
if ! python3 -c "import json; json.load(open('$TEMP_JSON'))" 2>/dev/null; then
    echo "WARNING: Generated JSON is invalid, attempting to fix..."
    # Fallback to simpler JSON
    cat > "$TEMP_JSON" << EOF
{
    "slicer_running": $SLICER_RUNNING,
    "segmentation_exists": $SEGMENTATION_EXISTS,
    "segmentation_volume_ml": $SEGMENTATION_VOLUME_ML,
    "frontal_ruler_exists": $FRONTAL_RULER_EXISTS,
    "frontal_horn_width_mm": $FRONTAL_WIDTH,
    "skull_ruler_exists": $SKULL_RULER_EXISTS,
    "skull_diameter_mm": $SKULL_DIAMETER,
    "evans_index_calculated": $EVANS_INDEX,
    "report_exists": $REPORT_EXISTS,
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END
}
EOF
fi

# Save result
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat "$RESULT_FILE"
echo ""
echo "=== Export Complete ==="