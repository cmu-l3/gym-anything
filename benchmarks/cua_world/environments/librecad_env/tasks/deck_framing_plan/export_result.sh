#!/bin/bash
set -e
echo "=== Exporting deck_framing_plan results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DXF_PATH="/home/ga/Documents/LibreCAD/deck_framing_plan.dxf"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze the DXF file using Python inside the container
# We do this here because ezdxf is installed in the container environment
cat > /tmp/analyze_dxf.py << 'EOF'
import sys
import json
import os
import math
import statistics

try:
    import ezdxf
except ImportError:
    print(json.dumps({"error": "ezdxf not installed"}))
    sys.exit(0)

file_path = "/home/ga/Documents/LibreCAD/deck_framing_plan.dxf"
result = {
    "exists": False,
    "valid_dxf": False,
    "layers_found": [],
    "entity_counts": {},
    "bounding_box": {"min_x": 0, "min_y": 0, "max_x": 0, "max_y": 0, "width": 0, "height": 0},
    "joist_analysis": {"count": 0, "spacing_std_dev": 0.0},
    "post_count": 0,
    "stairs_geometry": False,
    "dimension_count": 0,
    "total_entities": 0
}

if os.path.exists(file_path):
    result["exists"] = True
    try:
        doc = ezdxf.readfile(file_path)
        msp = doc.modelspace()
        result["valid_dxf"] = True
        
        # Analyze Layers
        result["layers_found"] = [layer.dxf.name.upper() for layer in doc.layers]
        
        # Analyze Entities
        entities = list(msp)
        result["total_entities"] = len(entities)
        
        xs = []
        ys = []
        
        joist_x_coords = []
        
        for e in entities:
            etype = e.dxftype()
            layer = e.dxf.layer.upper()
            
            # Entity counts
            result["entity_counts"][layer] = result["entity_counts"].get(layer, 0) + 1
            
            # Coordinate gathering for bounding box
            coords = []
            if hasattr(e.dxf, 'start'): coords.append(e.dxf.start)
            if hasattr(e.dxf, 'end'): coords.append(e.dxf.end)
            if hasattr(e.dxf, 'insert'): coords.append(e.dxf.insert)
            if hasattr(e.dxf, 'center'): coords.append(e.dxf.center) # Circle
            
            for p in coords:
                xs.append(p.x)
                ys.append(p.y)
                
            # Joist Analysis
            if layer == "JOISTS" and etype == "LINE":
                # Collect x coordinate (assuming vertical lines)
                if hasattr(e.dxf, 'start'):
                    joist_x_coords.append(e.dxf.start.x)
            
            # Post Analysis
            if layer == "POSTS":
                result["post_count"] += 1
                
            # Dimension Analysis
            if "DIMENSION" in etype:
                result["dimension_count"] += 1
            # Fallback: check if entity is on DIMENSIONS layer
            elif layer == "DIMENSIONS":
                result["dimension_count"] += 1

            # Stairs geometry check (looking for negative Y)
            if layer == "STAIRS":
                for p in coords:
                    if p.y < 0:
                        result["stairs_geometry"] = True

        # Calculate Bounding Box
        if xs and ys:
            result["bounding_box"] = {
                "min_x": min(xs), "max_x": max(xs),
                "min_y": min(ys), "max_y": max(ys),
                "width": max(xs) - min(xs),
                "height": max(ys) - min(ys)
            }
            
        # Joist Spacing Regularity
        if len(joist_x_coords) >= 3:
            joist_x_coords.sort()
            # Filter duplicates (lines might be drawn over each other or have start/end)
            unique_x = sorted(list(set([round(x, 1) for x in joist_x_coords])))
            result["joist_analysis"]["count"] = len(unique_x)
            
            if len(unique_x) > 1:
                spacings = [unique_x[i+1] - unique_x[i] for i in range(len(unique_x)-1)]
                if len(spacings) > 1:
                    result["joist_analysis"]["spacing_std_dev"] = statistics.stdev(spacings)
                else:
                    result["joist_analysis"]["spacing_std_dev"] = 0.0
                    
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
EOF

# Run the analysis script
python3 /tmp/analyze_dxf.py > /tmp/dxf_analysis.json 2>/dev/null || echo '{"error": "Analysis script failed"}' > /tmp/dxf_analysis.json

# 3. File Timestamp Check
FILE_MODIFIED_DURING_TASK="false"
if [ -f "$DXF_PATH" ]; then
    FILE_MTIME=$(stat -c %Y "$DXF_PATH")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
fi

# 4. Check if App is Running
APP_RUNNING="false"
if pgrep -f librecad > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "app_running": $APP_RUNNING,
    "dxf_metrics": $(cat /tmp/dxf_analysis.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="