#!/bin/bash
echo "=== Exporting Liver 3D Model Task Result ==="

source /workspace/scripts/task_utils.sh

# Get patient number
PATIENT_NUM=$(cat /tmp/ircadb_patient_num 2>/dev/null || echo "5")
IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

OUTPUT_LIVER_STL="$IRCADB_DIR/liver_model.stl"
OUTPUT_TUMOR_STL="$IRCADB_DIR/tumor_model.stl"
OUTPUT_REPORT="$IRCADB_DIR/model_report.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/liver_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export any segmentations from Slicer before closing
    cat > /tmp/export_liver_models.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/IRCADb"
os.makedirs(output_dir, exist_ok=True)

print("Checking for segmentations to export...")

# Find segmentation nodes
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

for seg_node in seg_nodes:
    print(f"Processing segmentation: {seg_node.GetName()}")
    segmentation = seg_node.GetSegmentation()
    n_segments = segmentation.GetNumberOfSegments()
    print(f"  Contains {n_segments} segments")
    
    for i in range(n_segments):
        segment_id = segmentation.GetNthSegmentID(i)
        segment = segmentation.GetSegment(segment_id)
        segment_name = segment.GetName().lower()
        print(f"    Segment: {segment.GetName()}")

# Find model nodes (if agent already created models)
model_nodes = slicer.util.getNodesByClass("vtkMRMLModelNode")
print(f"Found {len(model_nodes)} model node(s)")

for model_node in model_nodes:
    model_name = model_node.GetName().lower()
    print(f"  Model: {model_node.GetName()}")
    
    # Export liver model
    if 'liver' in model_name and 'tumor' not in model_name:
        stl_path = os.path.join(output_dir, "liver_model.stl")
        if slicer.util.saveNode(model_node, stl_path):
            print(f"    Exported to {stl_path}")
    
    # Export tumor model
    if 'tumor' in model_name:
        stl_path = os.path.join(output_dir, "tumor_model.stl")
        if slicer.util.saveNode(model_node, stl_path):
            print(f"    Exported to {stl_path}")

print("Export check complete")
PYEOF
    
    # Run the export script in Slicer (quick check)
    timeout 15 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_liver_models.py --no-main-window > /tmp/slicer_export.log 2>&1 || true
fi

# Check liver STL file
LIVER_STL_EXISTS="false"
LIVER_STL_SIZE="0"
LIVER_MTIME="0"
LIVER_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_LIVER_STL" ]; then
    LIVER_STL_EXISTS="true"
    LIVER_STL_SIZE=$(stat -c%s "$OUTPUT_LIVER_STL" 2>/dev/null || echo "0")
    LIVER_MTIME=$(stat -c%Y "$OUTPUT_LIVER_STL" 2>/dev/null || echo "0")
    if [ "$LIVER_MTIME" -gt "$TASK_START" ]; then
        LIVER_CREATED_DURING_TASK="true"
    fi
    echo "Liver STL: $OUTPUT_LIVER_STL (${LIVER_STL_SIZE} bytes, created_during_task=$LIVER_CREATED_DURING_TASK)"
else
    # Check alternative locations
    for alt_path in "$IRCADB_DIR/Liver.stl" "$IRCADB_DIR/liver.stl" "/home/ga/liver_model.stl"; do
        if [ -f "$alt_path" ]; then
            cp "$alt_path" "$OUTPUT_LIVER_STL" 2>/dev/null || true
            LIVER_STL_EXISTS="true"
            LIVER_STL_SIZE=$(stat -c%s "$OUTPUT_LIVER_STL" 2>/dev/null || echo "0")
            LIVER_MTIME=$(stat -c%Y "$alt_path" 2>/dev/null || echo "0")
            if [ "$LIVER_MTIME" -gt "$TASK_START" ]; then
                LIVER_CREATED_DURING_TASK="true"
            fi
            echo "Found liver STL at $alt_path, copied to $OUTPUT_LIVER_STL"
            break
        fi
    done
fi

# Check tumor STL file
TUMOR_STL_EXISTS="false"
TUMOR_STL_SIZE="0"
TUMOR_MTIME="0"
TUMOR_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_TUMOR_STL" ]; then
    TUMOR_STL_EXISTS="true"
    TUMOR_STL_SIZE=$(stat -c%s "$OUTPUT_TUMOR_STL" 2>/dev/null || echo "0")
    TUMOR_MTIME=$(stat -c%Y "$OUTPUT_TUMOR_STL" 2>/dev/null || echo "0")
    if [ "$TUMOR_MTIME" -gt "$TASK_START" ]; then
        TUMOR_CREATED_DURING_TASK="true"
    fi
    echo "Tumor STL: $OUTPUT_TUMOR_STL (${TUMOR_STL_SIZE} bytes, created_during_task=$TUMOR_CREATED_DURING_TASK)"
else
    # Check alternative locations
    for alt_path in "$IRCADB_DIR/Tumor.stl" "$IRCADB_DIR/tumor.stl" "/home/ga/tumor_model.stl"; do
        if [ -f "$alt_path" ]; then
            cp "$alt_path" "$OUTPUT_TUMOR_STL" 2>/dev/null || true
            TUMOR_STL_EXISTS="true"
            TUMOR_STL_SIZE=$(stat -c%s "$OUTPUT_TUMOR_STL" 2>/dev/null || echo "0")
            TUMOR_MTIME=$(stat -c%Y "$alt_path" 2>/dev/null || echo "0")
            if [ "$TUMOR_MTIME" -gt "$TASK_START" ]; then
                TUMOR_CREATED_DURING_TASK="true"
            fi
            echo "Found tumor STL at $alt_path, copied to $OUTPUT_TUMOR_STL"
            break
        fi
    done
fi

# Check report file
REPORT_EXISTS="false"
REPORTED_LIVER_VOL="0"
REPORTED_TUMOR_VOL="0"
REPORTED_TUMOR_COUNT="-1"
REPORTED_SMOOTHING="false"

if [ -f "$OUTPUT_REPORT" ]; then
    REPORT_EXISTS="true"
    REPORTED_LIVER_VOL=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(d.get('liver_volume_ml', 0))" 2>/dev/null || echo "0")
    REPORTED_TUMOR_VOL=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(d.get('tumor_volume_ml', 0))" 2>/dev/null || echo "0")
    REPORTED_TUMOR_COUNT=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(d.get('tumor_count', -1))" 2>/dev/null || echo "-1")
    REPORTED_SMOOTHING=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(str(d.get('smoothing_applied', False)).lower())" 2>/dev/null || echo "false")
    echo "Report found: liver_vol=$REPORTED_LIVER_VOL, tumor_vol=$REPORTED_TUMOR_VOL, count=$REPORTED_TUMOR_COUNT"
else
    # Check alternative locations
    for alt_path in "$IRCADB_DIR/report.json" "/home/ga/model_report.json"; do
        if [ -f "$alt_path" ]; then
            cp "$alt_path" "$OUTPUT_REPORT" 2>/dev/null || true
            REPORT_EXISTS="true"
            REPORTED_LIVER_VOL=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(d.get('liver_volume_ml', 0))" 2>/dev/null || echo "0")
            REPORTED_TUMOR_VOL=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(d.get('tumor_volume_ml', 0))" 2>/dev/null || echo "0")
            REPORTED_TUMOR_COUNT=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(d.get('tumor_count', -1))" 2>/dev/null || echo "-1")
            REPORTED_SMOOTHING=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(str(d.get('smoothing_applied', False)).lower())" 2>/dev/null || echo "false")
            echo "Found report at $alt_path"
            break
        fi
    done
fi

# Load ground truth
GT_FILE="$GROUND_TRUTH_DIR/ircadb_patient${PATIENT_NUM}_gt.json"
GT_LIVER_VOL="0"
GT_TUMOR_VOL="0"
GT_TUMOR_COUNT="0"

if [ -f "$GT_FILE" ]; then
    GT_LIVER_VOL=$(python3 -c "import json; d=json.load(open('$GT_FILE')); print(d.get('liver_volume_ml', 0))" 2>/dev/null || echo "0")
    GT_TUMOR_VOL=$(python3 -c "import json; d=json.load(open('$GT_FILE')); print(d.get('tumor_volume_ml', 0))" 2>/dev/null || echo "0")
    GT_TUMOR_COUNT=$(python3 -c "import json; d=json.load(open('$GT_FILE')); print(d.get('tumor_count', 0))" 2>/dev/null || echo "0")
    echo "Ground truth: liver_vol=$GT_LIVER_VOL, tumor_vol=$GT_TUMOR_VOL, count=$GT_TUMOR_COUNT"
fi

# Analyze STL files using Python
echo "Analyzing STL files..."

LIVER_ANALYSIS='{"watertight": false, "triangles": 0, "volume_ml": 0}'
TUMOR_ANALYSIS='{"watertight": false, "triangles": 0, "volume_ml": 0}'

if [ "$LIVER_STL_EXISTS" = "true" ] && [ "$LIVER_STL_SIZE" -gt 1000 ]; then
    LIVER_ANALYSIS=$(python3 << 'PYEOF'
import struct
import json
import sys

filepath = "/home/ga/Documents/SlicerData/IRCADb/liver_model.stl"
result = {"watertight": False, "triangles": 0, "volume_ml": 0.0}

try:
    with open(filepath, 'rb') as f:
        # Check if ASCII or binary
        header = f.read(80)
        if b'solid' in header[:6]:
            # Might be ASCII, try to detect
            f.seek(0)
            first_line = f.readline()
            if first_line.strip().startswith(b'solid'):
                # ASCII format - simplified handling
                f.seek(0)
                content = f.read().decode('ascii', errors='ignore')
                result['triangles'] = content.count('facet normal')
                print(json.dumps(result))
                sys.exit(0)
        
        # Binary STL
        f.seek(80)
        num_triangles = struct.unpack('<I', f.read(4))[0]
        result['triangles'] = num_triangles
        
        if num_triangles < 10 or num_triangles > 10000000:
            print(json.dumps(result))
            sys.exit(0)
        
        edges = {}
        volume = 0.0
        
        for _ in range(num_triangles):
            data = f.read(50)
            if len(data) < 50:
                break
            
            v1 = struct.unpack('<3f', data[12:24])
            v2 = struct.unpack('<3f', data[24:36])
            v3 = struct.unpack('<3f', data[36:48])
            
            # Track edges for watertight check
            for edge in [(v1, v2), (v2, v3), (v3, v1)]:
                e_key = tuple(sorted([tuple(round(c, 4) for c in edge[0]), 
                                       tuple(round(c, 4) for c in edge[1])]))
                edges[e_key] = edges.get(e_key, 0) + 1
            
            # Signed volume contribution
            volume += (v1[0] * (v2[1] * v3[2] - v3[1] * v2[2]) -
                       v2[0] * (v1[1] * v3[2] - v3[1] * v1[2]) +
                       v3[0] * (v1[1] * v2[2] - v2[1] * v1[2])) / 6.0
        
        # Check watertight: each edge should appear exactly twice
        edge_counts = list(edges.values())
        if edge_counts:
            result['watertight'] = all(c == 2 for c in edge_counts)
        
        result['volume_ml'] = abs(volume) / 1000.0  # mm³ to mL
        
except Exception as e:
    result['error'] = str(e)

print(json.dumps(result))
PYEOF
)
    echo "Liver analysis: $LIVER_ANALYSIS"
fi

if [ "$TUMOR_STL_EXISTS" = "true" ] && [ "$TUMOR_STL_SIZE" -gt 500 ]; then
    TUMOR_ANALYSIS=$(python3 << 'PYEOF'
import struct
import json
import sys

filepath = "/home/ga/Documents/SlicerData/IRCADb/tumor_model.stl"
result = {"watertight": False, "triangles": 0, "volume_ml": 0.0}

try:
    with open(filepath, 'rb') as f:
        header = f.read(80)
        if b'solid' in header[:6]:
            f.seek(0)
            first_line = f.readline()
            if first_line.strip().startswith(b'solid'):
                f.seek(0)
                content = f.read().decode('ascii', errors='ignore')
                result['triangles'] = content.count('facet normal')
                print(json.dumps(result))
                sys.exit(0)
        
        f.seek(80)
        num_triangles = struct.unpack('<I', f.read(4))[0]
        result['triangles'] = num_triangles
        
        if num_triangles < 5 or num_triangles > 10000000:
            print(json.dumps(result))
            sys.exit(0)
        
        edges = {}
        volume = 0.0
        
        for _ in range(num_triangles):
            data = f.read(50)
            if len(data) < 50:
                break
            
            v1 = struct.unpack('<3f', data[12:24])
            v2 = struct.unpack('<3f', data[24:36])
            v3 = struct.unpack('<3f', data[36:48])
            
            for edge in [(v1, v2), (v2, v3), (v3, v1)]:
                e_key = tuple(sorted([tuple(round(c, 4) for c in edge[0]), 
                                       tuple(round(c, 4) for c in edge[1])]))
                edges[e_key] = edges.get(e_key, 0) + 1
            
            volume += (v1[0] * (v2[1] * v3[2] - v3[1] * v2[2]) -
                       v2[0] * (v1[1] * v3[2] - v3[1] * v1[2]) +
                       v3[0] * (v1[1] * v2[2] - v2[1] * v1[2])) / 6.0
        
        edge_counts = list(edges.values())
        if edge_counts:
            result['watertight'] = all(c == 2 for c in edge_counts)
        
        result['volume_ml'] = abs(volume) / 1000.0

except Exception as e:
    result['error'] = str(e)

print(json.dumps(result))
PYEOF
)
    echo "Tumor analysis: $TUMOR_ANALYSIS"
fi

# Parse analysis results
LIVER_WATERTIGHT=$(echo "$LIVER_ANALYSIS" | python3 -c "import json,sys; print(str(json.load(sys.stdin).get('watertight', False)).lower())" 2>/dev/null || echo "false")
LIVER_TRIANGLES=$(echo "$LIVER_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('triangles', 0))" 2>/dev/null || echo "0")
LIVER_STL_VOLUME=$(echo "$LIVER_ANALYSIS" | python3 -c "import json,sys; print(round(json.load(sys.stdin).get('volume_ml', 0), 2))" 2>/dev/null || echo "0")

TUMOR_WATERTIGHT=$(echo "$TUMOR_ANALYSIS" | python3 -c "import json,sys; print(str(json.load(sys.stdin).get('watertight', False)).lower())" 2>/dev/null || echo "false")
TUMOR_TRIANGLES=$(echo "$TUMOR_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('triangles', 0))" 2>/dev/null || echo "0")
TUMOR_STL_VOLUME=$(echo "$TUMOR_ANALYSIS" | python3 -c "import json,sys; print(round(json.load(sys.stdin).get('volume_ml', 0), 2))" 2>/dev/null || echo "0")

# Copy ground truth for verifier
cp "$GT_FILE" /tmp/liver_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/liver_ground_truth.json 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "patient_num": "$PATIENT_NUM",
    "liver_stl_exists": $LIVER_STL_EXISTS,
    "liver_stl_size_bytes": $LIVER_STL_SIZE,
    "liver_created_during_task": $LIVER_CREATED_DURING_TASK,
    "liver_watertight": $LIVER_WATERTIGHT,
    "liver_triangles": $LIVER_TRIANGLES,
    "liver_stl_volume_ml": $LIVER_STL_VOLUME,
    "tumor_stl_exists": $TUMOR_STL_EXISTS,
    "tumor_stl_size_bytes": $TUMOR_STL_SIZE,
    "tumor_created_during_task": $TUMOR_CREATED_DURING_TASK,
    "tumor_watertight": $TUMOR_WATERTIGHT,
    "tumor_triangles": $TUMOR_TRIANGLES,
    "tumor_stl_volume_ml": $TUMOR_STL_VOLUME,
    "report_exists": $REPORT_EXISTS,
    "reported_liver_volume_ml": $REPORTED_LIVER_VOL,
    "reported_tumor_volume_ml": $REPORTED_TUMOR_VOL,
    "reported_tumor_count": $REPORTED_TUMOR_COUNT,
    "reported_smoothing": $REPORTED_SMOOTHING,
    "gt_liver_volume_ml": $GT_LIVER_VOL,
    "gt_tumor_volume_ml": $GT_TUMOR_VOL,
    "gt_tumor_count": $GT_TUMOR_COUNT,
    "screenshot_exists": $([ -f "/tmp/liver_final.png" ] && echo "true" || echo "false")
}
EOF

# Save result
rm -f /tmp/liver_task_result.json 2>/dev/null || sudo rm -f /tmp/liver_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/liver_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/liver_task_result.json
chmod 666 /tmp/liver_task_result.json 2>/dev/null || sudo chmod 666 /tmp/liver_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/liver_task_result.json
echo ""
echo "=== Export Complete ==="