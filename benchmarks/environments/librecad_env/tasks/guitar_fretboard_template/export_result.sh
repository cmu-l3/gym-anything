#!/bin/bash
echo "=== Exporting Guitar Fretboard Task Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/LibreCAD/fretboard_template.dxf"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if output file exists and timestamps
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

# ============================================================================
# PYTHON DXF ANALYSIS (Runs inside container to leverage installed ezdxf)
# ============================================================================
cat > /tmp/analyze_dxf.py << 'EOF'
import sys
import json
import math

try:
    import ezdxf
except ImportError:
    print(json.dumps({"error": "ezdxf not installed"}))
    sys.exit(0)

def analyze_fretboard(filepath):
    result = {
        "valid_dxf": False,
        "layers": [],
        "frets_x": [],
        "inlay_circles": [],
        "outline_segments": [],
        "error": None
    }
    
    try:
        doc = ezdxf.readfile(filepath)
        result["valid_dxf"] = True
        
        # Get layers
        result["layers"] = [layer.dxf.name for layer in doc.layers]
        
        # Analyze FRETS layer (expecting vertical lines)
        msp = doc.modelspace()
        frets = msp.query('LINE[layer=="FRETS"]')
        for line in frets:
            # For a vertical line, start.x should be approx equal to end.x
            # We store the average X
            x_pos = (line.dxf.start.x + line.dxf.end.x) / 2.0
            result["frets_x"].append(x_pos)
        
        result["frets_x"].sort()
        
        # Analyze INLAYS layer (expecting circles)
        inlays = msp.query('CIRCLE[layer=="INLAYS"]')
        for circle in inlays:
            result["inlay_circles"].append({
                "center": (circle.dxf.center.x, circle.dxf.center.y),
                "radius": circle.dxf.radius
            })
            
        # Analyze OUTLINE layer
        outline = msp.query('LINE[layer=="OUTLINE"]')
        for line in outline:
            result["outline_segments"].append({
                "start": (line.dxf.start.x, line.dxf.start.y),
                "end": (line.dxf.end.x, line.dxf.end.y)
            })
            
    except Exception as e:
        result["error"] = str(e)
        
    return result

if __name__ == "__main__":
    filepath = "/home/ga/Documents/LibreCAD/fretboard_template.dxf"
    data = analyze_fretboard(filepath)
    print(json.dumps(data))
EOF

# Run analysis if file exists
DXF_ANALYSIS="{}"
if [ "$OUTPUT_EXISTS" = "true" ]; then
    echo "Running DXF analysis..."
    DXF_ANALYSIS=$(python3 /tmp/analyze_dxf.py)
fi

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "dxf_analysis": $DXF_ANALYSIS
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="