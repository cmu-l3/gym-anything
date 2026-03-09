#!/bin/bash
echo "=== Exporting Retaining Wall Section results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_PATH="/home/ga/Documents/LibreCAD/retaining_wall_section.dxf"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if application is still running
APP_RUNNING=$(pgrep -f "librecad" > /dev/null && echo "true" || echo "false")

# Basic file checks
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

# Run geometric analysis using the container's python environment (where ezdxf is installed)
# We write a temporary python script to parse the DXF and output JSON analysis
cat > /tmp/analyze_dxf.py << 'EOF'
import sys
import json
import os

try:
    import ezdxf
    HAS_EZDXF = True
except ImportError:
    HAS_EZDXF = False

def analyze_dxf(filepath):
    result = {
        "valid_dxf": False,
        "layers": [],
        "entity_counts": {},
        "text_content": [],
        "circles": [],
        "polylines": [],
        "dimensions": 0,
        "error": None
    }
    
    if not os.path.exists(filepath):
        result["error"] = "File not found"
        return result

    if not HAS_EZDXF:
        result["error"] = "ezdxf library missing in container"
        return result

    try:
        doc = ezdxf.readfile(filepath)
        result["valid_dxf"] = True
        
        # Analyze Layers
        result["layers"] = [layer.dxf.name for layer in doc.layers]
        
        # Analyze Entities in Model Space
        msp = doc.modelspace()
        
        counts = {}
        for e in msp:
            etype = e.dxftype()
            counts[etype] = counts.get(etype, 0) + 1
            
            # Extract Text
            if etype in ['TEXT', 'MTEXT']:
                # MTEXT content might need handling, but usually .text or .plain_text() works
                text_val = ""
                if etype == 'TEXT':
                    text_val = e.dxf.text
                elif etype == 'MTEXT':
                    text_val = e.text  # or e.plain_text() in newer versions
                result["text_content"].append({
                    "text": text_val,
                    "layer": e.dxf.layer
                })
                
            # Extract Circles (for drain pipe)
            if etype == 'CIRCLE':
                result["circles"].append({
                    "center": list(e.dxf.center)[:2], # X, Y
                    "radius": e.dxf.radius,
                    "layer": e.dxf.layer
                })
                
            # Extract Dimensions
            if etype == 'DIMENSION':
                result["dimensions"] += 1
                
            # Extract Polylines/Lines (simplified check for bounding boxes)
            if etype in ['LWPOLYLINE', 'POLYLINE']:
                points = []
                if etype == 'LWPOLYLINE':
                    points = [list(p)[:2] for p in e.get_points()]
                result["polylines"].append({
                    "layer": e.dxf.layer,
                    "points": points,
                    "closed": e.is_closed
                })

        result["entity_counts"] = counts
        
    except Exception as e:
        result["error"] = str(e)
        result["valid_dxf"] = False
        
    return result

if __name__ == "__main__":
    filepath = sys.argv[1]
    analysis = analyze_dxf(filepath)
    print(json.dumps(analysis))
EOF

# Run the analysis script
DXF_ANALYSIS="{}"
if [ "$OUTPUT_EXISTS" = "true" ]; then
    # Use python3 from container (ensure it has permissions)
    chmod +x /tmp/analyze_dxf.py
    DXF_ANALYSIS=$(python3 /tmp/analyze_dxf.py "$OUTPUT_PATH" 2>/dev/null || echo '{"error": "Analysis script failed"}')
fi

# Clean up analysis script
rm -f /tmp/analyze_dxf.py

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
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
cat /tmp/task_result.json
echo "=== Export complete ==="