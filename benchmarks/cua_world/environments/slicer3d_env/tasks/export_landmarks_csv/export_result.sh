#!/bin/bash
echo "=== Exporting Export Landmarks to CSV Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Paths
OUTPUT_CSV="/home/ga/Documents/SlicerData/Exports/landmarks.csv"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/landmarks_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/landmarks_final.png 2>/dev/null || true

if [ -f /tmp/landmarks_final.png ]; then
    FINAL_SIZE=$(stat -c%s /tmp/landmarks_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SIZE} bytes"
fi

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
fi

# Try to export fiducials from Slicer if not already done
if [ "$SLICER_RUNNING" = "true" ] && [ ! -f "$OUTPUT_CSV" ]; then
    echo "CSV not found, attempting to export from Slicer..."
    
    # Create export script
    cat > /tmp/export_landmarks.py << 'PYEOF'
import slicer
import os
import csv

output_path = "/home/ga/Documents/SlicerData/Exports/landmarks.csv"
output_dir = os.path.dirname(output_path)
os.makedirs(output_dir, exist_ok=True)

# Find point list (fiducial) nodes
point_lists = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(point_lists)} fiducial list(s)")

all_fiducials = []

for node in point_lists:
    n_points = node.GetNumberOfControlPoints()
    print(f"  Node '{node.GetName()}' has {n_points} control points")
    
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        label = node.GetNthControlPointLabel(i)
        if not label:
            label = f"Point_{i+1}"
        
        all_fiducials.append({
            "label": label,
            "r": pos[0],
            "a": pos[1],
            "s": pos[2]
        })
        print(f"    {label}: R={pos[0]:.2f}, A={pos[1]:.2f}, S={pos[2]:.2f}")

if all_fiducials:
    print(f"Writing {len(all_fiducials)} fiducials to {output_path}")
    with open(output_path, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['label', 'r', 'a', 's'])
        writer.writeheader()
        writer.writerows(all_fiducials)
    print("Export complete")
else:
    print("No fiducials found to export")
PYEOF

    # Run the export script in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_landmarks.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_landmarks.py" 2>/dev/null || true
fi

# ============================================================
# CHECK CSV FILE
# ============================================================
CSV_EXISTS="false"
CSV_SIZE=0
CSV_MTIME=0
CSV_CREATED_DURING_TASK="false"
CSV_LINE_COUNT=0
CSV_HAS_HEADER="false"
CSV_LANDMARK_COUNT=0
CSV_CONTENT=""
LANDMARKS_FOUND="[]"
COORDINATES_VALID="false"

if [ -f "$OUTPUT_CSV" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$OUTPUT_CSV" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c%Y "$OUTPUT_CSV" 2>/dev/null || echo "0")
    CSV_LINE_COUNT=$(wc -l < "$OUTPUT_CSV" 2>/dev/null || echo "0")
    
    echo "CSV file found: $OUTPUT_CSV"
    echo "  Size: $CSV_SIZE bytes"
    echo "  Lines: $CSV_LINE_COUNT"
    
    # Check if created during task
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
        echo "  Created during task: YES"
    else
        echo "  Created during task: NO (existed before)"
    fi
    
    # Read and display content
    echo "  Content:"
    cat "$OUTPUT_CSV" | head -20
    
    # Store CSV content for parsing
    CSV_CONTENT=$(cat "$OUTPUT_CSV" 2>/dev/null || echo "")
    
    # Parse CSV using Python
    PARSE_RESULT=$(python3 << PYEOF
import csv
import json
import sys

csv_path = "$OUTPUT_CSV"
result = {
    "has_header": False,
    "landmark_count": 0,
    "landmarks": [],
    "coordinates_valid": False,
    "all_distinct": False,
    "parse_error": None
}

try:
    with open(csv_path, 'r') as f:
        content = f.read().strip()
        
    if not content:
        result["parse_error"] = "Empty file"
    else:
        lines = content.split('\n')
        
        # Check for header
        first_line = lines[0].lower()
        if 'label' in first_line or 'name' in first_line or 'r' in first_line.split(','):
            result["has_header"] = True
            data_lines = lines[1:]
        else:
            data_lines = lines
        
        # Parse landmarks
        landmarks = []
        for line in data_lines:
            if not line.strip():
                continue
            parts = line.strip().split(',')
            if len(parts) >= 4:
                try:
                    label = parts[0].strip().strip('"')
                    r = float(parts[1])
                    a = float(parts[2])
                    s = float(parts[3])
                    landmarks.append({
                        "label": label,
                        "r": r,
                        "a": a,
                        "s": s
                    })
                except (ValueError, IndexError):
                    pass
        
        result["landmark_count"] = len(landmarks)
        result["landmarks"] = landmarks
        
        # Check coordinate bounds
        all_valid = True
        for lm in landmarks:
            if not (-100 <= lm["r"] <= 100):
                all_valid = False
            if not (-150 <= lm["a"] <= 100):
                all_valid = False
            if not (-80 <= lm["s"] <= 100):
                all_valid = False
        result["coordinates_valid"] = all_valid and len(landmarks) > 0
        
        # Check all points are distinct (> 5mm apart)
        import math
        all_distinct = True
        for i, lm1 in enumerate(landmarks):
            for j, lm2 in enumerate(landmarks):
                if i >= j:
                    continue
                dist = math.sqrt(
                    (lm1["r"] - lm2["r"])**2 +
                    (lm1["a"] - lm2["a"])**2 +
                    (lm1["s"] - lm2["s"])**2
                )
                if dist < 5.0:
                    all_distinct = False
                    break
            if not all_distinct:
                break
        result["all_distinct"] = all_distinct

except Exception as e:
    result["parse_error"] = str(e)

print(json.dumps(result))
PYEOF
)
    
    echo "Parse result: $PARSE_RESULT"
    
    # Extract values from parse result
    CSV_HAS_HEADER=$(echo "$PARSE_RESULT" | python3 -c "import json,sys; print(str(json.load(sys.stdin).get('has_header', False)).lower())" 2>/dev/null || echo "false")
    CSV_LANDMARK_COUNT=$(echo "$PARSE_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('landmark_count', 0))" 2>/dev/null || echo "0")
    LANDMARKS_FOUND=$(echo "$PARSE_RESULT" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin).get('landmarks', [])))" 2>/dev/null || echo "[]")
    COORDINATES_VALID=$(echo "$PARSE_RESULT" | python3 -c "import json,sys; print(str(json.load(sys.stdin).get('coordinates_valid', False)).lower())" 2>/dev/null || echo "false")
    ALL_DISTINCT=$(echo "$PARSE_RESULT" | python3 -c "import json,sys; print(str(json.load(sys.stdin).get('all_distinct', False)).lower())" 2>/dev/null || echo "false")
    
else
    echo "CSV file NOT found at $OUTPUT_CSV"
    
    # Search for any CSV files that might have been saved elsewhere
    echo "Searching for CSV files in common locations..."
    find /home/ga -name "*.csv" -newer /tmp/task_start_time.txt 2>/dev/null | head -5
fi

# ============================================================
# CHECK SLICER SCENE STATE
# ============================================================
FIDUCIALS_IN_SCENE=0
SCENE_FIDUCIAL_NAMES="[]"

if [ "$SLICER_RUNNING" = "true" ]; then
    # Try to query Slicer for fiducials
    SCENE_CHECK=$(python3 << 'PYEOF' 2>/dev/null || echo '{"fiducials_in_scene": 0, "names": []}')
import json
# This would need to connect to Slicer - skip if not possible
result = {"fiducials_in_scene": 0, "names": []}
print(json.dumps(result))
PYEOF
    
    FIDUCIALS_IN_SCENE=$(echo "$SCENE_CHECK" | python3 -c "import json,sys; print(json.load(sys.stdin).get('fiducials_in_scene', 0))" 2>/dev/null || echo "0")
fi

# Check for Slicer markup files that might indicate fiducials were placed
MRK_FILES=$(find /home/ga -name "*.mrk.json" -newer /tmp/task_start_time.txt 2>/dev/null | wc -l || echo "0")
FCSV_FILES=$(find /home/ga -name "*.fcsv" -newer /tmp/task_start_time.txt 2>/dev/null | wc -l || echo "0")

echo "Markup files created during task: $MRK_FILES .mrk.json, $FCSV_FILES .fcsv"

# ============================================================
# CREATE RESULT JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_sec": $((TASK_END - TASK_START)),
    "slicer_was_running": $SLICER_RUNNING,
    "csv_exists": $CSV_EXISTS,
    "csv_size_bytes": $CSV_SIZE,
    "csv_mtime": $CSV_MTIME,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "csv_line_count": $CSV_LINE_COUNT,
    "csv_has_header": $CSV_HAS_HEADER,
    "csv_landmark_count": $CSV_LANDMARK_COUNT,
    "landmarks_found": $LANDMARKS_FOUND,
    "coordinates_valid": $COORDINATES_VALID,
    "all_distinct": ${ALL_DISTINCT:-false},
    "fiducials_in_scene": $FIDUCIALS_IN_SCENE,
    "mrk_files_created": $MRK_FILES,
    "fcsv_files_created": $FCSV_FILES,
    "screenshot_final_path": "/tmp/landmarks_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/landmarks_task_result.json 2>/dev/null || sudo rm -f /tmp/landmarks_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/landmarks_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/landmarks_task_result.json
chmod 666 /tmp/landmarks_task_result.json 2>/dev/null || sudo chmod 666 /tmp/landmarks_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/landmarks_task_result.json"
cat /tmp/landmarks_task_result.json
echo ""
echo "=== Export Complete ==="