#!/bin/bash
echo "=== Exporting septic_drainfield_layout results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/LibreCAD/septic_plan.dxf"
ANALYSIS_JSON="/tmp/dxf_analysis.json"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check if output file exists and timestamps
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Run internal analysis script using container's Python environment (which has ezdxf)
# We generate a Python script on the fly to analyze the DXF
cat > /tmp/analyze_dxf.py << 'EOF'
import json
import sys
import os

try:
    import ezdxf
    from ezdxf.document import Drawing
except ImportError:
    print(json.dumps({"error": "ezdxf not installed"}))
    sys.exit(0)

def analyze_dxf(filepath):
    if not os.path.exists(filepath):
        return {"error": "File not found"}

    try:
        doc = ezdxf.readfile(filepath)
    except Exception as e:
        return {"error": f"Failed to parse DXF: {str(e)}"}

    msp = doc.modelspace()
    
    # Analyze Layers
    layers = [layer.dxf.name for layer in doc.layers]
    
    # Analyze Entities by Layer
    entities = {}
    for layer_name in ["DBOX", "TRENCHES", "PIPES", "LABELS"]:
        # Case-insensitive search for layer name
        actual_name = next((l for l in layers if l.upper() == layer_name), None)
        if not actual_name:
            entities[layer_name] = {"count": 0, "objects": []}
            continue
            
        objs = msp.query(f'*[layer=="{actual_name}"]')
        obj_data = []
        for obj in objs:
            data = {"type": obj.dxftype()}
            if obj.dxftype() == 'LINE':
                data["start"] = list(obj.dxf.start)[:2]
                data["end"] = list(obj.dxf.end)[:2]
            elif obj.dxftype() in ['LWPOLYLINE', 'POLYLINE']:
                # Get bounding box for polylines
                try:
                    if obj.dxftype() == 'LWPOLYLINE':
                        points = obj.get_points()
                    else:
                        points = [v.dxf.location for v in obj.vertices]
                    
                    xs = [p[0] for p in points]
                    ys = [p[1] for p in points]
                    if xs and ys:
                        data["bbox"] = [min(xs), min(ys), max(xs), max(ys)]
                        data["center"] = [(min(xs)+max(xs))/2, (min(ys)+max(ys))/2]
                        data["width"] = max(xs) - min(xs)
                        data["height"] = max(ys) - min(ys)
                except:
                    pass
            elif obj.dxftype() in ['TEXT', 'MTEXT']:
                data["text"] = obj.dxf.text if obj.dxftype() == 'TEXT' else obj.text
                
            obj_data.append(data)
            
        entities[layer_name] = {"count": len(objs), "objects": obj_data}

    return {
        "valid_dxf": True,
        "layers": layers,
        "entities": entities
    }

if __name__ == "__main__":
    result = analyze_dxf("/home/ga/Documents/LibreCAD/septic_plan.dxf")
    print(json.dumps(result))
EOF

# Run the analysis
if [ "$OUTPUT_EXISTS" = "true" ]; then
    python3 /tmp/analyze_dxf.py > "$ANALYSIS_JSON" 2>/dev/null || echo '{"error": "Analysis script failed"}' > "$ANALYSIS_JSON"
else
    echo '{"valid_dxf": false, "error": "No output file"}' > "$ANALYSIS_JSON"
fi

# 4. Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "dxf_analysis_path": "$ANALYSIS_JSON"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="