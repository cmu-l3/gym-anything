#!/bin/bash
echo "=== Exporting Line Intensity Profile Task Result ==="

source /workspace/scripts/task_utils.sh

# Get timing information
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_DURATION=$((TASK_END - TASK_START))
echo "Task duration: ${TASK_DURATION}s"

# Define paths
OUTPUT_DIR="/home/ga/Documents/SlicerData/Exports"
OUTPUT_CSV="$OUTPUT_DIR/line_profile_output.csv"

# Take final screenshot
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    FINAL_SCREENSHOT_SIZE=$(stat -c%s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot: $FINAL_SCREENSHOT_SIZE bytes"
fi

# ============================================================
# CHECK SLICER STATE
# ============================================================
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
fi

# Get window information
WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
echo "Current windows: $WINDOWS_LIST"

LINE_PROFILE_VISIBLE="false"
if echo "$WINDOWS_LIST" | grep -qi "Line Profile\|LineProfile"; then
    LINE_PROFILE_VISIBLE="true"
    echo "Line Profile module appears to be active"
fi

PLOT_VISIBLE="false"
if echo "$WINDOWS_LIST" | grep -qi "plot\|chart\|graph"; then
    PLOT_VISIBLE="true"
    echo "Plot window detected"
fi

# ============================================================
# EXTRACT LINE MARKUP INFORMATION FROM SLICER
# ============================================================
echo "Extracting line markup data from Slicer..."

LINE_MARKUP_EXISTS="false"
NUM_CONTROL_POINTS=0
LINE_LENGTH_MM=0
LINE_P1="[0,0,0]"
LINE_P2="[0,0,0]"
LINE_Z_COORD=0
ENDPOINTS_IN_BOUNDS="false"

# Create extraction script
cat > /tmp/extract_line_data.py << 'PYEOF'
import slicer
import json
import os
import math

output_data = {
    "line_markup_exists": False,
    "num_control_points": 0,
    "line_length_mm": 0,
    "p1": [0, 0, 0],
    "p2": [0, 0, 0],
    "line_z_coord": 0,
    "endpoints_in_bounds": False,
    "volume_loaded": False,
    "volume_dimensions": [0, 0, 0],
    "volume_bounds": [0, 0, 0, 0, 0, 0],
    "line_nodes_found": 0
}

try:
    # Check for loaded volume
    volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
    if volume_nodes:
        output_data["volume_loaded"] = True
        vol = volume_nodes[0]
        dims = vol.GetImageData().GetDimensions() if vol.GetImageData() else [0,0,0]
        output_data["volume_dimensions"] = list(dims)
        
        bounds = [0]*6
        vol.GetRASBounds(bounds)
        output_data["volume_bounds"] = bounds
    
    # Find line markups
    line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
    output_data["line_nodes_found"] = len(line_nodes)
    
    if line_nodes:
        # Use first line node (or find longest one)
        best_line = None
        best_length = 0
        
        for node in line_nodes:
            if node.GetNumberOfControlPoints() >= 2:
                p1 = [0.0, 0.0, 0.0]
                p2 = [0.0, 0.0, 0.0]
                node.GetNthControlPointPosition(0, p1)
                node.GetNthControlPointPosition(1, p2)
                length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
                
                if length > best_length:
                    best_length = length
                    best_line = node
        
        if best_line:
            output_data["line_markup_exists"] = True
            output_data["num_control_points"] = best_line.GetNumberOfControlPoints()
            
            p1 = [0.0, 0.0, 0.0]
            p2 = [0.0, 0.0, 0.0]
            best_line.GetNthControlPointPosition(0, p1)
            best_line.GetNthControlPointPosition(1, p2)
            
            output_data["p1"] = p1
            output_data["p2"] = p2
            output_data["line_length_mm"] = best_length
            output_data["line_z_coord"] = (p1[2] + p2[2]) / 2.0
            
            # Check if endpoints are within volume bounds
            if output_data["volume_loaded"]:
                bounds = output_data["volume_bounds"]
                in_bounds = True
                for coord in [p1, p2]:
                    if not (bounds[0] <= coord[0] <= bounds[1] and
                            bounds[2] <= coord[1] <= bounds[3] and
                            bounds[4] <= coord[2] <= bounds[5]):
                        in_bounds = False
                        break
                output_data["endpoints_in_bounds"] = in_bounds

except Exception as e:
    output_data["error"] = str(e)

# Save to file
with open("/tmp/line_markup_data.json", "w") as f:
    json.dump(output_data, f, indent=2)

print("Line markup data exported")
PYEOF

# Run extraction in Slicer
if [ "$SLICER_RUNNING" = "true" ]; then
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/extract_line_data.py --no-main-window > /tmp/slicer_extract.log 2>&1 &
    EXTRACT_PID=$!
    sleep 8
    kill $EXTRACT_PID 2>/dev/null || true
fi

# Read extracted data
if [ -f /tmp/line_markup_data.json ]; then
    echo "Line markup data extracted:"
    cat /tmp/line_markup_data.json
    
    LINE_MARKUP_EXISTS=$(python3 -c "import json; print('true' if json.load(open('/tmp/line_markup_data.json')).get('line_markup_exists', False) else 'false')" 2>/dev/null || echo "false")
    NUM_CONTROL_POINTS=$(python3 -c "import json; print(json.load(open('/tmp/line_markup_data.json')).get('num_control_points', 0))" 2>/dev/null || echo "0")
    LINE_LENGTH_MM=$(python3 -c "import json; print(json.load(open('/tmp/line_markup_data.json')).get('line_length_mm', 0))" 2>/dev/null || echo "0")
    LINE_P1=$(python3 -c "import json; print(json.load(open('/tmp/line_markup_data.json')).get('p1', [0,0,0]))" 2>/dev/null || echo "[0,0,0]")
    LINE_P2=$(python3 -c "import json; print(json.load(open('/tmp/line_markup_data.json')).get('p2', [0,0,0]))" 2>/dev/null || echo "[0,0,0]")
    ENDPOINTS_IN_BOUNDS=$(python3 -c "import json; print('true' if json.load(open('/tmp/line_markup_data.json')).get('endpoints_in_bounds', False) else 'false')" 2>/dev/null || echo "false")
fi

# ============================================================
# CHECK OUTPUT CSV FILE
# ============================================================
echo "Checking output CSV file..."

CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
CSV_SIZE_BYTES=0
CSV_NUM_ROWS=0
CSV_HAS_DISTANCE_COL="false"
CSV_HAS_INTENSITY_COL="false"
CSV_INTENSITY_MIN=0
CSV_INTENSITY_MAX=0
CSV_INTENSITY_MEAN=0
CSV_INTENSITY_STDDEV=0
CSV_VALID_DATA="false"

if [ -f "$OUTPUT_CSV" ]; then
    CSV_EXISTS="true"
    CSV_SIZE_BYTES=$(stat -c%s "$OUTPUT_CSV" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c%Y "$OUTPUT_CSV" 2>/dev/null || echo "0")
    
    echo "CSV file found: $CSV_SIZE_BYTES bytes"
    
    # Check if created during task
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
        echo "CSV was created during task"
    else
        echo "WARNING: CSV existed before task started"
    fi
    
    # Analyze CSV content
    python3 << PYEOF
import csv
import json
import statistics

csv_path = "$OUTPUT_CSV"
analysis = {
    "num_rows": 0,
    "has_distance_col": False,
    "has_intensity_col": False,
    "intensity_values": [],
    "distance_values": [],
    "valid_data": False
}

try:
    with open(csv_path, 'r') as f:
        # Try to detect delimiter
        sample = f.read(2048)
        f.seek(0)
        
        # Detect delimiter
        if '\\t' in sample:
            delimiter = '\\t'
        elif ';' in sample:
            delimiter = ';'
        else:
            delimiter = ','
        
        reader = csv.DictReader(f, delimiter=delimiter)
        headers = reader.fieldnames or []
        
        # Check for expected columns (Slicer Line Profile uses various names)
        header_lower = [h.lower() for h in headers]
        
        for h in header_lower:
            if 'distance' in h or 'position' in h or 'mm' in h:
                analysis["has_distance_col"] = True
            if 'intensity' in h or 'value' in h or 'gray' in h or 'scalar' in h:
                analysis["has_intensity_col"] = True
        
        # Read data rows
        rows = list(reader)
        analysis["num_rows"] = len(rows)
        
        # Extract numeric values
        for row in rows:
            for key, val in row.items():
                try:
                    num_val = float(val)
                    key_lower = key.lower()
                    if 'distance' in key_lower or 'position' in key_lower:
                        analysis["distance_values"].append(num_val)
                    elif 'intensity' in key_lower or 'value' in key_lower:
                        analysis["intensity_values"].append(num_val)
                    else:
                        # If column names not recognized, collect all numeric columns
                        if len(analysis["intensity_values"]) == 0:
                            analysis["intensity_values"].append(num_val)
                except (ValueError, TypeError):
                    continue
        
        # Check for valid data
        if len(analysis["intensity_values"]) > 10:
            analysis["valid_data"] = True
            analysis["intensity_min"] = min(analysis["intensity_values"])
            analysis["intensity_max"] = max(analysis["intensity_values"])
            analysis["intensity_mean"] = statistics.mean(analysis["intensity_values"])
            if len(analysis["intensity_values"]) > 1:
                analysis["intensity_stddev"] = statistics.stdev(analysis["intensity_values"])
            else:
                analysis["intensity_stddev"] = 0
        
        # Remove large arrays before saving
        analysis["num_intensity_values"] = len(analysis["intensity_values"])
        analysis["num_distance_values"] = len(analysis["distance_values"])
        del analysis["intensity_values"]
        del analysis["distance_values"]
        
except Exception as e:
    analysis["error"] = str(e)

with open("/tmp/csv_analysis.json", "w") as f:
    json.dump(analysis, f, indent=2)

print("CSV analysis complete")
PYEOF

    # Read CSV analysis
    if [ -f /tmp/csv_analysis.json ]; then
        echo "CSV analysis:"
        cat /tmp/csv_analysis.json
        
        CSV_NUM_ROWS=$(python3 -c "import json; print(json.load(open('/tmp/csv_analysis.json')).get('num_rows', 0))" 2>/dev/null || echo "0")
        CSV_HAS_DISTANCE_COL=$(python3 -c "import json; print('true' if json.load(open('/tmp/csv_analysis.json')).get('has_distance_col', False) else 'false')" 2>/dev/null || echo "false")
        CSV_HAS_INTENSITY_COL=$(python3 -c "import json; print('true' if json.load(open('/tmp/csv_analysis.json')).get('has_intensity_col', False) else 'false')" 2>/dev/null || echo "false")
        CSV_INTENSITY_MIN=$(python3 -c "import json; print(json.load(open('/tmp/csv_analysis.json')).get('intensity_min', 0))" 2>/dev/null || echo "0")
        CSV_INTENSITY_MAX=$(python3 -c "import json; print(json.load(open('/tmp/csv_analysis.json')).get('intensity_max', 0))" 2>/dev/null || echo "0")
        CSV_INTENSITY_MEAN=$(python3 -c "import json; print(json.load(open('/tmp/csv_analysis.json')).get('intensity_mean', 0))" 2>/dev/null || echo "0")
        CSV_INTENSITY_STDDEV=$(python3 -c "import json; print(json.load(open('/tmp/csv_analysis.json')).get('intensity_stddev', 0))" 2>/dev/null || echo "0")
        CSV_VALID_DATA=$(python3 -c "import json; print('true' if json.load(open('/tmp/csv_analysis.json')).get('valid_data', False) else 'false')" 2>/dev/null || echo "false")
    fi
else
    echo "Output CSV not found at $OUTPUT_CSV"
    # Search for any CSV files that might contain profile data
    echo "Searching for alternative CSV files..."
    find /home/ga -name "*.csv" -newer /tmp/task_start_time.txt 2>/dev/null | head -5
fi

# ============================================================
# BUILD RESULT JSON
# ============================================================
echo "Building result JSON..."

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_sec": $TASK_DURATION,
    
    "slicer_was_running": $SLICER_RUNNING,
    "line_profile_visible": $LINE_PROFILE_VISIBLE,
    "plot_visible": $PLOT_VISIBLE,
    
    "line_markup_exists": $LINE_MARKUP_EXISTS,
    "num_control_points": $NUM_CONTROL_POINTS,
    "line_length_mm": $LINE_LENGTH_MM,
    "line_p1": $LINE_P1,
    "line_p2": $LINE_P2,
    "endpoints_in_bounds": $ENDPOINTS_IN_BOUNDS,
    
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "csv_size_bytes": $CSV_SIZE_BYTES,
    "csv_num_rows": $CSV_NUM_ROWS,
    "csv_has_distance_col": $CSV_HAS_DISTANCE_COL,
    "csv_has_intensity_col": $CSV_HAS_INTENSITY_COL,
    "csv_intensity_min": $CSV_INTENSITY_MIN,
    "csv_intensity_max": $CSV_INTENSITY_MAX,
    "csv_intensity_mean": $CSV_INTENSITY_MEAN,
    "csv_intensity_stddev": $CSV_INTENSITY_STDDEV,
    "csv_valid_data": $CSV_VALID_DATA,
    
    "final_screenshot_exists": $([ -f /tmp/task_final.png ] && echo "true" || echo "false"),
    "final_screenshot_size": ${FINAL_SCREENSHOT_SIZE:-0},
    
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/line_profile_result.json 2>/dev/null || sudo rm -f /tmp/line_profile_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/line_profile_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/line_profile_result.json
chmod 666 /tmp/line_profile_result.json 2>/dev/null || sudo chmod 666 /tmp/line_profile_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/line_profile_result.json

echo ""
echo "=== Export Complete ==="