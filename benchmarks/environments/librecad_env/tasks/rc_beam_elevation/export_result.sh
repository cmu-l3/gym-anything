#!/bin/bash
set -e
echo "=== Exporting RC Beam Elevation Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/LibreCAD/rc_beam_elevation.dxf"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check file stats
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Verify file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_CREATED_DURING_TASK="false"
fi

# ------------------------------------------------------------------
# Internal DXF Analysis (Running inside container where ezdxf exists)
# ------------------------------------------------------------------
ANALYSIS_JSON="/tmp/dxf_analysis.json"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    cat > /tmp/analyze_dxf.py << 'EOF'
import sys
import json
import ezdxf
import statistics

def analyze_dxf(file_path):
    result = {
        "valid_dxf": False,
        "layers": [],
        "concrete_bounds": None,
        "rebar_y_coords": [],
        "stirrup_x_coords": [],
        "stirrup_spacing_median": 0,
        "error": None
    }
    
    try:
        doc = ezdxf.readfile(file_path)
        msp = doc.modelspace()
        result["valid_dxf"] = True
        
        # 1. Analyze Layers
        result["layers"] = [layer.dxf.name for layer in doc.layers]
        
        # 2. Analyze Concrete Geometry (Layer: CONCRETE)
        # We look for lines or polylines that might form the beam
        concrete_lines = msp.query('LINE[layer=="CONCRETE"]')
        x_vals = []
        y_vals = []
        for line in concrete_lines:
            x_vals.extend([line.dxf.start.x, line.dxf.end.x])
            y_vals.extend([line.dxf.start.y, line.dxf.end.y])
            
        # Also check polylines (LWPOLYLINE)
        concrete_polys = msp.query('LWPOLYLINE[layer=="CONCRETE"]')
        for poly in concrete_polys:
            for point in poly.get_points():
                x_vals.append(point[0])
                y_vals.append(point[1])

        if x_vals and y_vals:
            result["concrete_bounds"] = {
                "min_x": min(x_vals),
                "max_x": max(x_vals),
                "min_y": min(y_vals),
                "max_y": max(y_vals),
                "width": max(x_vals) - min(x_vals),
                "height": max(y_vals) - min(y_vals)
            }

        # 3. Analyze Main Rebar (Layer: REBAR_MAIN)
        # We expect horizontal lines. We care about Y coordinates (Cover).
        main_lines = msp.query('LINE[layer=="REBAR_MAIN"]')
        rebar_ys = []
        for line in main_lines:
            # Check if roughly horizontal
            if abs(line.dxf.start.y - line.dxf.end.y) < 5.0:
                rebar_ys.append(round((line.dxf.start.y + line.dxf.end.y) / 2, 1))
        
        result["rebar_y_coords"] = sorted(list(set(rebar_ys)))

        # 4. Analyze Stirrups (Layer: REBAR_STIRRUPS)
        # We expect vertical lines. We care about X coordinates (Spacing).
        stirrup_lines = msp.query('LINE[layer=="REBAR_STIRRUPS"]')
        stirrup_xs = []
        for line in stirrup_lines:
            # Check if roughly vertical
            if abs(line.dxf.start.x - line.dxf.end.x) < 5.0:
                stirrup_xs.append((line.dxf.start.x + line.dxf.end.x) / 2)
        
        stirrup_xs.sort()
        result["stirrup_x_coords"] = stirrup_xs
        result["stirrup_count"] = len(stirrup_xs)

        # Calculate Spacing
        if len(stirrup_xs) > 1:
            diffs = [stirrup_xs[i+1] - stirrup_xs[i] for i in range(len(stirrup_xs)-1)]
            result["stirrup_spacing_median"] = statistics.median(diffs) if diffs else 0
            
    except Exception as e:
        result["error"] = str(e)
        
    return result

if __name__ == "__main__":
    data = analyze_dxf(sys.argv[1])
    with open(sys.argv[2], 'w') as f:
        json.dump(data, f)
EOF

    # Run the python script
    python3 /tmp/analyze_dxf.py "$OUTPUT_PATH" "$ANALYSIS_JSON" || echo '{"error": "Analysis script failed"}' > "$ANALYSIS_JSON"
else
    echo '{"error": "File not found"}' > "$ANALYSIS_JSON"
fi

# Merge results
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "dxf_analysis": $(cat "$ANALYSIS_JSON" 2>/dev/null || echo "{}")
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="