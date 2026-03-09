#!/bin/bash
echo "=== Exporting garden_bed_layout results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/LibreCAD/garden_layout.dxf"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Stats
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if App is Running
APP_RUNNING=$(pgrep -f "librecad" > /dev/null && echo "true" || echo "false")

# 4. Perform Detailed DXF Analysis inside container (using installed ezdxf)
# We generate a separate JSON for the geometry analysis
cat > /tmp/analyze_dxf.py << 'PYEOF'
import sys
import json
import math
import os

output = {
    "valid_dxf": False,
    "layers_found": [],
    "entities": {
        "boundary_rect": False,
        "ellipse_valid": False,
        "corner_circles": 0,
        "fountain_circle": False,
        "walkway_lines": 0,
        "dimension_count": 0
    },
    "error": ""
}

try:
    import ezdxf
    dxf_path = "/home/ga/Documents/LibreCAD/garden_layout.dxf"
    
    if os.path.exists(dxf_path):
        try:
            doc = ezdxf.readfile(dxf_path)
            output["valid_dxf"] = True
            msp = doc.modelspace()
            
            # Check Layers
            required_layers = ["BOUNDARY", "BEDS", "WALKWAYS", "FOUNTAIN", "DIMENSIONS"]
            existing_layers = [layer.dxf.name.upper() for layer in doc.layers]
            output["layers_found"] = [l for l in required_layers if l in existing_layers]
            
            # Helper: dist
            def dist(p1, p2):
                return math.sqrt((p1[0]-p2[0])**2 + (p1[1]-p2[1])**2)

            # Analyze Entities
            for e in msp:
                layer = e.dxf.layer.upper() if hasattr(e.dxf, 'layer') else ""
                etype = e.dxftype()
                
                # Boundary Rectangle (Lines or Polyline on BOUNDARY)
                if layer == "BOUNDARY":
                    if etype == "LWPOLYLINE":
                        # Check extents
                        bbox = e.bounding_box() # (minx, miny), (maxx, maxy) usually in newer ezdxf, or we compute points
                        # Simple point check
                        pts = list(e.get_points(format='xy'))
                        if pts:
                            xs = [p[0] for p in pts]
                            ys = [p[1] for p in pts]
                            w, h = max(xs)-min(xs), max(ys)-min(ys)
                            if abs(w-12) < 0.5 and abs(h-9) < 0.5:
                                output["entities"]["boundary_rect"] = True
                    elif etype == "LINE":
                        # We count lines later if polyline not found
                        pass

                # Ellipse on BEDS
                if layer == "BEDS" andVP etype == "ELLIPSE":
                    cx, cy = e.dxf.center.x, e.dxf.center.y
                    # Major axis vector
                    mx, my = e.dxf.major_axis.x, e.dxf.major_axis.y
                    major_r = math.sqrt(mx**2 + my**2)
                    ratio = e.dxf.ratio
                    minor_r = major_r * ratio
                    
                    # Check params: Center (6, 4.5), Radii approx 3.0 and 1.8
                    if dist((cx, cy), (6, 4.5)) < 0.5:
                        # Allow swap of major/minor logic if rotated
                        dims = sorted([major_r, minor_r])
                        if abs(dims[1] - 3.0) < 0.3 and abs(dims[0] - 1.8) < 0.3:
                            output["entities"]["ellipse_valid"] = True

                # Corner Circles on BEDS
                if layer == "BEDS" and etype == "CIRCLE":
                    cx, cy, r = e.dxf.center.x, e.dxf.center.y, e.dxf.radius
                    target_centers = [(2,2), (10,2), (2,7), (10,7)]
                    for tc in target_centers:
                        if dist((cx, cy), tc) < 0.5 and abs(r - 0.9) < 0.15:
                            output["entities"]["corner_circles"] += 1
                            break # Count each circle only once for closest target

                # Fountain Circle on FOUNTAIN
                if layer == "FOUNTAIN" and etype == "CIRCLE":
                    cx, cy, r = e.dxf.center.x, e.dxf.center.y, e.dxf.radius
                    if dist((cx, cy), (6, 4.5)) < 0.5 and abs(r - 0.45) < 0.1:
                        output["entities"]["fountain_circle"] = True

                # Walkway Lines
                if layer == "WALKWAYS" and etype == "LINE":
                    # Just count them for now, detailed coord check is complex for simple export
                    output["entities"]["walkway_lines"] += 1

                # Dimensions
                if "DIMENSION" in etype or layer == "DIMENSIONS":
                    output["entities"]["dimension_count"] += 1
            
            # Fallback for boundary lines
            if not output["entities"]["boundary_rect"]:
                b_lines = [e for e in msp if e.dxf.layer.upper() == "BOUNDARY" and e.dxftype() == "LINE"]
                if len(b_lines) >= 4:
                    output["entities"]["boundary_rect"] = True

        except Exception as e:
            output["error"] = str(e)
    
except ImportError:
    output["error"] = "ezdxf not installed"

print(json.dumps(output))
PYEOF

# Run analysis
python3 /tmp/analyze_dxf.py > /tmp/dxf_analysis.json 2>/dev/null || echo "{}" > /tmp/dxf_analysis.json

# 5. Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move results to standard locations
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json /tmp/dxf_analysis.json /tmp/task_final.png 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result export complete."
cat /tmp/task_result.json