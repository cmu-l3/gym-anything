#!/bin/bash
echo "=== Exporting Packaging Die-Cut Result ==="

# 1. Capture basic task info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/LibreCAD/box_dieline.dxf"

# 2. Capture final screenshot (for VLM verification)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Check if output file exists and was created during task
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Run internal python script to analyze DXF content
# We run this INSIDE the container because it has ezdxf installed
# and the host might not.
cat > /tmp/analyze_dxf.py << 'EOF'
import sys
import json
import os

try:
    import ezdxf
    from ezdxf import colors
except ImportError:
    print(json.dumps({"error": "ezdxf not installed"}))
    sys.exit(0)

dxf_path = "/home/ga/Documents/LibreCAD/box_dieline.dxf"
result = {
    "valid_dxf": False,
    "layers": {},
    "entity_counts": {},
    "geometry_check": {
        "fold_lines": 0,
        "cut_lines": 0,
        "glue_tab_chamfer": False
    },
    "error": None
}

if not os.path.exists(dxf_path):
    result["error"] = "File not found"
    print(json.dumps(result))
    sys.exit(0)

try:
    doc = ezdxf.readfile(dxf_path)
    result["valid_dxf"] = True
    
    # Analyze Layers
    for layer in doc.layers:
        result["layers"][layer.dxf.name] = {
            "color": layer.dxf.color,
            "linetype": layer.dxf.linetype
        }
    
    # Analyze Entities (Modelspace)
    msp = doc.modelspace()
    
    # Check specifically for the required geometry
    # Fold Lines: Should be on FOLD layer
    fold_lines = msp.query('LINE[layer=="FOLD"]')
    result["entity_counts"]["fold_lines"] = len(fold_lines)
    
    # Simple bounding box check for folds
    for e in fold_lines:
        # Check for vertical creases at x=60, 120, 180
        start = e.dxf.start
        end = e.dxf.end
        # Vertical check
        if abs(start.x - end.x) < 1.0:
            if 59 < start.x < 181: # Roughly within the panel range
                result["geometry_check"]["fold_lines"] += 1
        # Horizontal check
        elif abs(start.y - end.y) < 1.0:
             if abs(start.y) < 1.0 or abs(start.y - 100) < 1.0:
                 result["geometry_check"]["fold_lines"] += 1

    # Cut Lines: Should be on CUT layer
    cut_lines = msp.query('LINE[layer=="CUT"]')
    result["entity_counts"]["cut_lines"] = len(cut_lines)
    
    # Check for Chamfer on glue tab
    # Look for diagonal lines near x=240-255, y=90-100 or y=0-10
    chamfer_found = False
    for e in cut_lines:
        s, e_pt = e.dxf.start, e.dxf.end
        # Check for diagonal: dx != 0 and dy != 0
        if abs(s.x - e_pt.x) > 1 and abs(s.y - e_pt.y) > 1:
            # Check if it's in the glue tab region (X > 230)
            if s.x > 230 or e_pt.x > 230:
                chamfer_found = True
    
    result["geometry_check"]["glue_tab_chamfer"] = chamfer_found

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

# Run analysis script
python3 /tmp/analyze_dxf.py > /tmp/dxf_analysis.json 2>/dev/null || echo '{"error": "Analysis script failed"}' > /tmp/dxf_analysis.json

# 5. Combine into final result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size": $FILE_SIZE,
    "dxf_analysis": $(cat /tmp/dxf_analysis.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Ensure permissions for copying
chmod 666 /tmp/task_result.json
chmod 666 /tmp/task_final.png 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="