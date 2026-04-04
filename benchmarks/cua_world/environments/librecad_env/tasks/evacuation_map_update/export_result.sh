#!/bin/bash
echo "=== Exporting evacuation_map_update results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_PATH="/home/ga/Documents/LibreCAD/evacuation_plan.dxf"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check output file status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Run internal verification script using the container's python and ezdxf
    # This generates /tmp/dxf_analysis.json
    echo "Running internal DXF analysis..."
    python3 - << 'EOF'
import sys
import json
import math

try:
    import ezdxf
    from ezdxf import units
except ImportError:
    print("ezdxf not installed", file=sys.stderr)
    sys.exit(0)

OUTPUT_FILE = "/home/ga/Documents/LibreCAD/evacuation_plan.dxf"
RESULT_FILE = "/tmp/dxf_analysis.json"

analysis = {
    "is_valid_dxf": False,
    "layer_safety_exists": False,
    "layer_safety_color": None,
    "route_valid": False,
    "marker_valid": False,
    "fe_symbol_valid": False,
    "text_labels_found": [],
    "error": None
}

def dist(p1, p2):
    return math.hypot(p1[0] - p2[0], p1[1] - p2[1])

try:
    doc = ezdxf.readfile(OUTPUT_FILE)
    analysis["is_valid_dxf"] = True
    msp = doc.modelspace()

    # 1. Check Layer
    if "SAFETY" in doc.layers:
        analysis["layer_safety_exists"] = True
        layer = doc.layers.get("SAFETY")
        analysis["layer_safety_color"] = layer.dxf.color # Should be 1 (Red)

    # Filter entities on SAFETY layer
    safety_entities = [e for e in msp if e.dxf.layer == "SAFETY"]
    
    # 2. Check Marker (Circle at 300,300, r=25)
    circles = [e for e in safety_entities if e.dxftype() == "CIRCLE"]
    for c in circles:
        center = c.dxf.center
        radius = c.dxf.radius
        if dist(center, (300, 300)) < 5.0 and abs(radius - 25) < 2.0:
            analysis["marker_valid"] = True
            break
            
    # 3. Check FE Symbol (Square centered at 500,300, size 50)
    # Could be Polyline or 4 Lines
    # BBox check: approx (475,275) to (525,325)
    # Simple check: Look for geometry roughly matching this bbox
    fe_candidates = [e for e in safety_entities if e.dxftype() in ("LWPOLYLINE", "POLYLINE")]
    for p in fe_candidates:
        # Check bounding box
        if not p.has_dxf_attribute('const_width'): # Just simple check
            pass
        # ezdxf allows getting points
        points = list(p.points()) if hasattr(p, 'points') else []
        # Rough check for square shape centered at 500,300
        # Instead of complex geom, let's check if we have entities in that area
        pass

    # Alternative FE Check: Look for lines/polylines bounded in that region
    fe_ents = 0
    for e in safety_entities:
        if e.dxftype() in ("LINE", "LWPOLYLINE"):
            # Bounding box or points check would be complex, let's look for vertices
            # We'll rely on the verifier to trust a simplified check or VLM for the shape details
            # But let's try to find a closed loop near 500,300
            pass
    
    # Robust FE Check: Check for lines/polylines with vertices near the corners
    corners = [(475, 275), (525, 275), (525, 325), (475, 325)]
    # We look for geometry connecting these approximate points
    matched_corners = 0
    all_points = []
    
    for e in safety_entities:
        if e.dxftype() == "LWPOLYLINE":
            all_points.extend([p[:2] for p in e.get_points()])
        elif e.dxftype() == "LINE":
            all_points.append(e.dxf.start[:2])
            all_points.append(e.dxf.end[:2])
            
    for cx, cy in corners:
        for px, py in all_points:
            if dist((cx, cy), (px, py)) < 5.0:
                matched_corners += 1
                break
    if matched_corners >= 3: # Allow slight imperfection
        analysis["fe_symbol_valid"] = True

    # 4. Check Route (300,300) -> (300,600) -> (800,600)
    # Look for connectivity
    has_leg1 = False # 300,300 to 300,600
    has_leg2 = False # 300,600 to 800,600
    
    # Check linear entities
    for e in safety_entities:
        pts = []
        if e.dxftype() == "LINE":
            pts = [e.dxf.start[:2], e.dxf.end[:2]]
        elif e.dxftype() == "LWPOLYLINE":
            pts = [p[:2] for p in e.get_points()]
            
        # Check segments
        for i in range(len(pts) - 1):
            p1 = pts[i]
            p2 = pts[i+1]
            
            # Check Leg 1
            if (dist(p1, (300,300)) < 5 and dist(p2, (300,600)) < 5) or \
               (dist(p2, (300,300)) < 5 and dist(p1, (300,600)) < 5):
                has_leg1 = True
                
            # Check Leg 2
            if (dist(p1, (300,600)) < 5 and dist(p2, (800,600)) < 5) or \
               (dist(p2, (300,600)) < 5 and dist(p1, (800,600)) < 5):
                has_leg2 = True
                
    if has_leg1 and has_leg2:
        analysis["route_valid"] = True

    # 5. Check Text
    text_ents = [e for e in safety_entities if e.dxftype() in ("TEXT", "MTEXT")]
    for t in text_ents:
        content = t.dxf.text.upper() if t.dxftype() == "TEXT" else t.text.upper()
        if "HERE" in content: analysis["text_labels_found"].append("YOU ARE HERE")
        if "EXIT" in content: analysis["text_labels_found"].append("EXIT")
        if "FE" in content: analysis["text_labels_found"].append("FE")
        
    analysis["text_labels_found"] = list(set(analysis["text_labels_found"]))

except Exception as e:
    analysis["error"] = str(e)

with open(RESULT_FILE, 'w') as f:
    json.dump(analysis, f, indent=2)
EOF

fi

# Create main result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $(pgrep -f "librecad" > /dev/null && echo "true" || echo "false")
}
EOF

# Move result to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result export complete."
cat /tmp/task_result.json