#!/bin/bash
echo "=== Exporting staircase_plan_view results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/LibreCAD/staircase_plan.dxf"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check file existence and timestamp
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Run internal python script to parse DXF (using ezdxf installed in container)
# This generates a detailed analysis JSON that the verifier can read without needing ezdxf on host
cat << 'EOF' > /tmp/analyze_dxf.py
import ezdxf
import json
import sys
import os

result = {
    "valid_dxf": False,
    "layers": [],
    "horizontal_lines": 0,
    "correct_width_lines": 0,
    "correct_spacing_lines": 0,
    "text_contents": [],
    "dimensions_count": 0,
    "entities_in_layers": {}
}

try:
    doc = ezdxf.readfile("/home/ga/Documents/LibreCAD/staircase_plan.dxf")
    result["valid_dxf"] = True
    
    # Analyze layers
    result["layers"] = [layer.dxf.name for layer in doc.layers]
    
    msp = doc.modelspace()
    
    # Analyze Treads layer
    tread_lines = msp.query('LINE[layer=="Treads"]')
    y_coords = []
    
    for line in tread_lines:
        start = line.dxf.start
        end = line.dxf.end
        
        # Check horizontal
        if abs(start.y - end.y) < 5.0: # 5mm tolerance
            result["horizontal_lines"] += 1
            y_coords.append(start.y)
            
            # Check width (length)
            length = abs(start.x - end.x)
            if abs(length - 900.0) < 50.0:
                result["correct_width_lines"] += 1

    # Check spacing
    y_coords.sort()
    valid_spacings = 0
    if len(y_coords) > 1:
        for i in range(len(y_coords) - 1):
            diff = y_coords[i+1] - y_coords[i]
            if abs(diff - 250.0) < 25.0: # 10% tolerance on 250mm
                valid_spacings += 1
    result["correct_spacing_lines"] = valid_spacings

    # Analyze Labels
    texts = msp.query('TEXT MTEXT[layer=="Labels"]')
    result["text_contents"] = [e.dxf.text for e in texts if hasattr(e.dxf, 'text')]
    # MTEXT sometimes stores text differently, keep it simple for now
    
    # Analyze Dimensions
    dims = msp.query('DIMENSION[layer=="Dimensions"]')
    result["dimensions_count"] = len(dims)
    
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

# Run the analysis if file exists
DXF_ANALYSIS="{}"
if [ "$FILE_EXISTS" = "true" ]; then
    # Ensure ezdxf is available (it should be from env setup)
    if python3 -c "import ezdxf" 2>/dev/null; then
        DXF_ANALYSIS=$(python3 /tmp/analyze_dxf.py)
    else
        DXF_ANALYSIS="{\"error\": \"ezdxf not installed in container\"}"
    fi
fi

# 4. Create final result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "dxf_analysis": $DXF_ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Permission fix
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="