#!/bin/bash
echo "=== Exporting solar_array_plan results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/LibreCAD/solar_array_plan.dxf"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if output file exists and when it was modified
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if app is still running
APP_RUNNING=$(pgrep -f "librecad" > /dev/null && echo "true" || echo "false")

# ============================================================================
# Run internal Python script to analyze the DXF structure
# We do this INSIDE the container because it has ezdxf installed.
# The verifier.py (outside) will just read the JSON summary.
# ============================================================================
cat > /tmp/analyze_dxf.py << 'EOF'
import sys
import json
import os

try:
    import ezdxf
    EZDXF_AVAILABLE = True
except ImportError:
    EZDXF_AVAILABLE = False

def get_rect_bounds(entity):
    """Extract bounding box (x, y, w, h) from LWPOLYLINE."""
    try:
        if entity.dxftype() == 'LWPOLYLINE':
            pts = list(entity.get_points(format='xy'))
            if len(pts) >= 4:
                xs = [p[0] for p in pts]
                ys = [p[1] for p in pts]
                return {
                    'x': min(xs), 'y': min(ys),
                    'w': max(xs) - min(xs), 'h': max(ys) - min(ys)
                }
    except:
        pass
    return None

def analyze(filepath):
    result = {
        'parsed': False,
        'layers': {},
        'rectangles': [],
        'lines': [],
        'error': None
    }
    
    if not EZDXF_AVAILABLE:
        result['error'] = "ezdxf library not found"
        return result
        
    try:
        doc = ezdxf.readfile(filepath)
        result['parsed'] = True
        
        # Analyze Layers
        for layer in doc.layers:
            result['layers'][layer.dxf.name] = {
                'color': layer.dxf.color
            }
            
        # Analyze Entities in Modelspace
        msp = doc.modelspace()
        
        # Collect Rectangles (LWPOLYLINE)
        for entity in msp.query('LWPOLYLINE'):
            bounds = get_rect_bounds(entity)
            if bounds:
                result['rectangles'].append({
                    'layer': entity.dxf.layer,
                    'bounds': bounds
                })
                
        # Collect Lines
        for entity in msp.query('LINE'):
            result['lines'].append({
                'layer': entity.dxf.layer,
                'start': [entity.dxf.start.x, entity.dxf.start.y],
                'end': [entity.dxf.end.x, entity.dxf.end.y]
            })
            
    except Exception as e:
        result['error'] = str(e)
        
    return result

if __name__ == "__main__":
    filepath = sys.argv[1]
    if os.path.exists(filepath):
        data = analyze(filepath)
    else:
        data = {'parsed': False, 'error': 'File not found'}
    
    print(json.dumps(data))
EOF

# Run the analysis if file exists
DXF_ANALYSIS="{}"
if [ "$OUTPUT_EXISTS" = "true" ]; then
    DXF_ANALYSIS=$(python3 /tmp/analyze_dxf.py "$OUTPUT_PATH")
fi

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "dxf_data": $DXF_ANALYSIS
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="