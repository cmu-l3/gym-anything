#!/bin/bash
echo "=== Exporting Scissor Lift Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/LibreCAD/scissor_lift_study.dxf"

# Basic File Checks
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
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

# Application State Check
APP_RUNNING=$(pgrep -f "librecad" > /dev/null && echo "true" || echo "false")

# Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ==============================================================================
# DXF ANALYSIS (Run inside container because host might not have ezdxf)
# ==============================================================================
DXF_ANALYSIS_JSON="{}"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    echo "Running internal DXF analysis..."
    
    # Create a temporary python script to analyze the DXF
    cat > /tmp/analyze_dxf.py << 'EOF'
import sys
import json
import math
import ezdxf

def analyze_dxf(file_path):
    result = {
        "valid_dxf": False,
        "layers": [],
        "structure_lines": [],
        "pin_circles": [],
        "max_y": 0.0,
        "dimension_count": 0,
        "error": None
    }
    
    try:
        doc = ezdxf.readfile(file_path)
        result["valid_dxf"] = True
        
        # 1. Check Layers
        result["layers"] = [layer.dxf.name for layer in doc.layers]
        
        msp = doc.modelspace()
        
        # 2. Analyze Structure Lines (Lengths)
        lines = msp.query('LINE[layer=="STRUCTURE"]')
        for line in lines:
            start = line.dxf.start
            end = line.dxf.end
            length = math.sqrt((end.x - start.x)**2 + (end.y - start.y)**2)
            result["structure_lines"].append(length)
            
            # Track Max Y for structure
            result["max_y"] = max(result["max_y"], start.y, end.y)

        # 3. Analyze Pins (Circles)
        circles = msp.query('CIRCLE[layer=="PINS"]')
        for circle in circles:
            result["pin_circles"].append(circle.dxf.radius * 2) # Diameter
            result["max_y"] = max(result["max_y"], circle.dxf.center.y)

        # 4. Analyze Platform (for height check)
        platform_ents = msp.query('*[layer=="PLATFORM"]')
        for ent in platform_ents:
            if ent.dxftype() == 'LINE':
                result["max_y"] = max(result["max_y"], ent.dxf.start.y, ent.dxf.end.y)
        
        # 5. Check Dimensions
        dims = msp.query('DIMENSION')
        result["dimension_count"] = len(dims)
        
    except Exception as e:
        result["error"] = str(e)
        
    return result

if __name__ == "__main__":
    try:
        path = sys.argv[1]
        data = analyze_dxf(path)
        print(json.dumps(data))
    except Exception as e:
        print(json.dumps({"error": str(e)}))
EOF

    # Execute the python script
    DXF_ANALYSIS_JSON=$(python3 /tmp/analyze_dxf.py "$OUTPUT_PATH")
fi

# Combine everything into final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "dxf_analysis": $DXF_ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON" /tmp/analyze_dxf.py

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="