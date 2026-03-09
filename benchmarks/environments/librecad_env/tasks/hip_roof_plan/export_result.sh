#!/bin/bash
echo "=== Exporting Hip Roof Plan Result ==="

# Record timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
OUTPUT_PATH="/home/ga/Documents/LibreCAD/hip_roof_plan.dxf"
ANALYSIS_JSON="/tmp/dxf_analysis.json"

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Basic File Checks
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if created during task
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

# 3. Advanced DXF Geometry Analysis (Running inside container where ezdxf is installed)
# We run this python script to parse the DXF and output a JSON analysis
cat > /tmp/analyze_dxf.py << 'EOF'
import sys
import json
import math

try:
    import ezdxf
    from ezdxf.math import Vec3
except ImportError:
    print(json.dumps({"error": "ezdxf not installed"}))
    sys.exit(0)

def analyze_dxf(filepath):
    result = {
        "is_valid": False,
        "layers": [],
        "text_content": [],
        "wall_corners_found": 0,
        "valley_line_found": False,
        "ridge_intersection_found": False,
        "hip_lines_count": 0
    }
    
    try:
        doc = ezdxf.readfile(filepath)
        msp = doc.modelspace()
        result["is_valid"] = True
        
        # Check Layers
        result["layers"] = [layer.dxf.name for layer in doc.layers]
        
        # Check Text
        for text in msp.query('TEXT MTEXT'):
            # Access text content differently for TEXT and MTEXT if needed, 
            # but usually plain_text() or just text attribute works
            content = ""
            if text.dxftype() == 'TEXT':
                content = text.dxf.text
            elif text.dxftype() == 'MTEXT':
                content = text.text  # plain text
            if content:
                result["text_content"].append(content)
        
        # Geometry Helpers
        def is_point_close(v, target, tol=0.1):
            return abs(v.x - target[0]) < tol and abs(v.y - target[1]) < tol

        def is_line_segment(entity, p1, p2, tol=0.1):
            if entity.dxftype() not in ['LINE']: 
                return False
            start = entity.dxf.start
            end = entity.dxf.end
            # Check both directions
            return (is_point_close(start, p1, tol) and is_point_close(end, p2, tol)) or \
                   (is_point_close(start, p2, tol) and is_point_close(end, p1, tol))

        # 1. Analyze Walls (Polyline or Lines)
        # Target corners: (0,0), (12,0), (12,6), (6,6), (6,10), (0,10)
        wall_targets = [(0,0), (12,0), (12,6), (6,6), (6,10), (0,10)]
        found_walls = set()
        
        # Check Lines
        for line in msp.query('LINE'):
            # Check for Valley (6,6) -> (3,3)
            if is_line_segment(line, (6,6), (3,3)):
                result["valley_line_found"] = True
            
            # Check Hips/Ridges connected to (3,3)
            if is_point_close(line.dxf.start, (3,3)) or is_point_close(line.dxf.end, (3,3)):
                result["ridge_intersection_found"] = True

        # Check Polylines for walls (often agents use polylines for outlines)
        # Or individual lines. We'll look for endpoints matching corners.
        corners_hit = set()
        for entity in msp.query('LINE LWPOLYLINE POLYLINE'):
            points = []
            if entity.dxftype() == 'LINE':
                points = [entity.dxf.start, entity.dxf.end]
            elif entity.dxftype() == 'LWPOLYLINE':
                points = entity.get_points(format='xy')
            
            for p in points:
                for idx, target in enumerate(wall_targets):
                    if is_point_close(Vec3(p), target):
                        corners_hit.add(idx)
        
        result["wall_corners_found"] = len(corners_hit)

    except Exception as e:
        result["error"] = str(e)
        
    return result

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"error": "No file provided"}))
    else:
        print(json.dumps(analyze_dxf(sys.argv[1])))
EOF

# Run analysis if output exists
if [ "$OUTPUT_EXISTS" = "true" ]; then
    python3 /tmp/analyze_dxf.py "$OUTPUT_PATH" > "$ANALYSIS_JSON" 2>/dev/null || echo "{}" > "$ANALYSIS_JSON"
else
    echo '{"is_valid": false}' > "$ANALYSIS_JSON"
fi

# 4. Check if App was running
APP_RUNNING=$(pgrep -f "librecad" > /dev/null && echo "true" || echo "false")

# 5. Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "dxf_analysis": $(cat "$ANALYSIS_JSON"),
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