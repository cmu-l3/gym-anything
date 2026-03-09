#!/bin/bash
echo "=== Exporting Crane Lift Plan Results ==="

# 1. Basic File Checks
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/LibreCAD/crane_lift_plan.dxf"
ANALYSIS_JSON="/tmp/dxf_analysis.json"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. DXF Content Analysis (Run inside container using ezdxf)
# We generate a python script to parse the DXF and extract geometric features
# because the host verifier might not have ezdxf installed.

cat > /tmp/analyze_dxf.py << 'EOF'
import sys
import json
import math

try:
    import ezdxf
    from ezdxf.document import Drawing
except ImportError:
    print(json.dumps({"error": "ezdxf not installed"}))
    sys.exit(0)

def analyze_dxf(filepath):
    try:
        doc = ezdxf.readfile(filepath)
        msp = doc.modelspace()
    except Exception as e:
        return {"error": str(e), "valid_dxf": False}

    result = {
        "valid_dxf": True,
        "layers": [layer.dxf.name for layer in doc.layers],
        "entities": {}
    }

    # Analyze specific layers
    required_layers = ["CRANE_SETUP", "BUILDING", "LOAD_PATH", "ANNOTATIONS"]
    
    for layer in required_layers:
        entities = msp.query(f'*[layer=="{layer}"]')
        layer_data = {
            "count": len(entities),
            "circles": [],
            "lines": [],
            "polylines": [],
            "texts": []
        }
        
        for e in entities:
            dxftype = e.dxftype()
            
            if dxftype == "CIRCLE":
                layer_data["circles"].append({
                    "center": list(e.dxf.center)[:2], # X, Y only
                    "radius": e.dxf.radius
                })
            elif dxftype == "LINE":
                layer_data["lines"].append({
                    "start": list(e.dxf.start)[:2],
                    "end": list(e.dxf.end)[:2]
                })
            elif dxftype == "LWPOLYLINE":
                points = []
                with e.points() as p:
                    points = [list(pt)[:2] for pt in p]
                layer_data["polylines"].append({
                    "points": points,
                    "is_closed": e.closed
                })
            elif dxftype in ["TEXT", "MTEXT"]:
                # Handle both TEXT and MTEXT content
                text_content = e.text if dxftype == "TEXT" else e.text
                layer_data["texts"].append(text_content)
        
        result["entities"][layer] = layer_data

    return result

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"error": "No file provided"}))
        sys.exit(1)
        
    filepath = sys.argv[1]
    analysis = analyze_dxf(filepath)
    print(json.dumps(analysis))
EOF

# Run the analysis script if file exists
if [ "$FILE_EXISTS" = "true" ]; then
    echo "Running DXF analysis..."
    python3 /tmp/analyze_dxf.py "$OUTPUT_FILE" > "$ANALYSIS_JSON" 2>/dev/null || echo '{"error": "Analysis script failed"}' > "$ANALYSIS_JSON"
else
    echo '{"valid_dxf": false, "reason": "File not found"}' > "$ANALYSIS_JSON"
fi

# 3. Create Final Result JSON
# Merge bash checks and python analysis
TEMP_RESULT=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_RESULT" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "dxf_analysis": $(cat "$ANALYSIS_JSON"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_RESULT" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="