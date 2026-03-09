#!/bin/bash
echo "=== Exporting bicycle_frame_geometry result ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/LibreCAD/bicycle_geometry.dxf"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check file existence and timestamp
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

# Run geometric analysis using the container's python/ezdxf
# We do this here because the host environment might not have ezdxf installed.
echo "Running geometric analysis inside container..."
cat > /tmp/analyze_dxf.py << 'EOF'
import sys
import json
import math
import ezdxf

def analyze_geometry(dxf_path):
    results = {
        "valid_dxf": False,
        "layers_found": [],
        "entities_count": 0,
        "geometry_score": 0,
        "nodes_found": {},
        "feedback": []
    }

    try:
        doc = ezdxf.readfile(dxf_path)
        results["valid_dxf"] = True
    except Exception as e:
        results["feedback"].append(f"Failed to load DXF: {str(e)}")
        return results

    # Check Layers
    required_layers = ["FRAME", "DIMENSIONS", "NOTES"]
    existing_layers = [layer.dxf.name for layer in doc.layers]
    results["layers_found"] = existing_layers
    
    layer_score = 0
    for req in required_layers:
        # Case insensitive check
        if any(req.lower() == l.lower() for l in existing_layers):
            layer_score += 10/3
        else:
            results["feedback"].append(f"Missing layer: {req}")
    
    # Check Entities
    msp = doc.modelspace()
    results["entities_count"] = len(list(msp))
    
    # Define Target Points
    # BB: (0,0)
    # Rear Axle: (-430, -70)
    # HT Top: (385, 590)
    # ST Top: 540 @ 106.5 deg -> (-153.4, 517.7)
    # HT Bottom: (385, 590) + 160 @ -108.5 deg -> (385-50.7, 590-151.7) -> (334.3, 438.3)
    
    targets = {
        "BB": (0, 0),
        "RearAxle": (-430, -70),
        "HT_Top": (385, 590),
        "ST_Top": (-153.4, 517.7),
        "HT_Bottom": (334.3, 438.3)
    }
    
    # Find points in drawing (endpoints of lines and centers of circles)
    found_points = []
    
    for e in msp:
        if e.dxftype() == 'CIRCLE':
            found_points.append(e.dxf.center)
        elif e.dxftype() == 'LINE':
            found_points.append(e.dxf.start)
            found_points.append(e.dxf.end)
    
    # Check proximity to targets
    node_score = 0
    points_found_status = {}
    
    for name, (tx, ty) in targets.items():
        found = False
        min_dist = 1000
        for p in found_points:
            dist = math.sqrt((p[0] - tx)**2 + (p[1] - ty)**2)
            if dist < min_dist:
                min_dist = dist
            if dist < 5.0: # 5mm tolerance
                found = True
                break
        
        points_found_status[name] = {"found": found, "min_dist": min_dist}
        if found:
            node_score += 10  # 5 nodes * 10 = 50 pts max
        else:
            results["feedback"].append(f"Node {name} not found at expected {tx},{ty} (nearest: {min_dist:.1f}mm)")

    results["nodes_found"] = points_found_status
    results["geometry_score"] = node_score + int(layer_score)
    
    # Check Dimensions and Text
    has_dims = any(e.dxftype() == 'DIMENSION' for e in msp)
    has_text = any(e.dxftype() in ['TEXT', 'MTEXT'] for e in msp)
    
    if has_dims: results["geometry_score"] += 5
    else: results["feedback"].append("No dimensions found")
    
    if has_text: results["geometry_score"] += 5
    else: results["feedback"].append("No text labels found")

    return results

if __name__ == "__main__":
    path = sys.argv[1]
    if len(sys.argv) > 1 else ""
    data = analyze_geometry(path)
    print(json.dumps(data))
EOF

GEOMETRY_ANALYSIS="{}"
if [ "$OUTPUT_EXISTS" = "true" ]; then
    GEOMETRY_ANALYSIS=$(python3 /tmp/analyze_dxf.py "$OUTPUT_PATH")
fi

# Clean up temp script
rm -f /tmp/analyze_dxf.py

# Create final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "geometry_analysis": $GEOMETRY_ANALYSIS
}
EOF

# Save to public location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="