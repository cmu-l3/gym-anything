#!/bin/bash
echo "=== Exporting t_intersection_plan results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/LibreCAD/t_intersection.dxf"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check File Stats
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
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

# 2. Check App State
APP_RUNNING=$(pgrep -f "librecad" > /dev/null && echo "true" || echo "false")

# 3. Analyze DXF Content using Python (inside container where ezdxf is installed)
# We embed a python script to parse the DXF and extract semantic data for the verifier
echo "Running DXF analysis..."

cat > /tmp/analyze_dxf.py << 'EOF'
import sys
import json
import os

try:
    import ezdxf
    has_ezdxf = True
except ImportError:
    has_ezdxf = False

file_path = "/home/ga/Documents/LibreCAD/t_intersection.dxf"
result = {
    "valid_dxf": False,
    "layers": [],
    "entity_counts": {},
    "curb_arcs": [],
    "text_content": [],
    "dimensions_count": 0,
    "error": None
}

if not os.path.exists(file_path):
    result["error"] = "File not found"
    print(json.dumps(result))
    sys.exit(0)

if not has_ezdxf:
    result["error"] = "ezdxf library not available in container"
    print(json.dumps(result))
    sys.exit(0)

try:
    doc = ezdxf.readfile(file_path)
    result["valid_dxf"] = True
    
    # Get layers
    result["layers"] = [layer.dxf.name.upper() for layer in doc.layers]
    
    msp = doc.modelspace()
    
    # Count entities per layer
    counts = {}
    for e in msp:
        layer = e.dxf.layer.upper()
        etype = e.dxftype()
        key = f"{layer}:{etype}"
        counts[key] = counts.get(key, 0) + 1
        
        # Check specific entities
        if layer == "CURB_RETURN" and etype == "ARC":
            result["curb_arcs"].append({
                "radius": e.dxf.radius,
                "center": list(e.dxf.center)[:2]
            })
            
        if etype in ["TEXT", "MTEXT"]:
            text = e.dxf.text if etype == "TEXT" else e.text
            result["text_content"].append(text)
            
        if "DIMENSION" in etype:
            result["dimensions_count"] += 1
            
    result["entity_counts"] = counts
    
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

# Execute the analysis script
python3 /tmp/analyze_dxf.py > /tmp/dxf_analysis.json 2>/dev/null || echo '{"error": "Analysis script failed"}' > /tmp/dxf_analysis.json

# Read the analysis result
DXF_ANALYSIS=$(cat /tmp/dxf_analysis.json)

# Combine into final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "dxf_analysis": $DXF_ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="