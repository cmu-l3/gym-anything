#!/bin/bash
echo "=== Exporting Roundabout Design Result ==="

# 1. Capture Final State Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Basic File Checks
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DXF_PATH="/home/ga/Documents/LibreCAD/roundabout_design.dxf"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$DXF_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$DXF_PATH")
    FILE_MTIME=$(stat -c %Y "$DXF_PATH")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Advanced DXF Analysis (Running inside container where ezdxf is installed)
# We create a python script on the fly to parse the DXF and output JSON.
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

DXF_FILE = "/home/ga/Documents/LibreCAD/roundabout_design.dxf"

result = {
    "valid_dxf": False,
    "layers_found": [],
    "island_circle_found": False,
    "outer_circle_untouched": False, # If true, they didn't trim
    "outer_arcs_found": False,       # Segments of the trimmed circle
    "fillet_arcs_found": False,      # The R=6 fillets
    "roadway_lines_found": False,    # The straight legs
    "error": None
}

try:
    doc = ezdxf.readfile(DXF_FILE)
    result["valid_dxf"] = True
    msp = doc.modelspace()

    # Check Layers
    expected_layers = ["ISLAND", "ROADWAY", "CENTERLINES"]
    found_layers = []
    for layer in doc.layers:
        name = layer.dxf.name.upper()
        if name in expected_layers:
            found_layers.append(name)
    result["layers_found"] = found_layers

    # Check Island (Layer ISLAND, Circle, R=4, Center~100,100)
    # Allow small tolerance
    island_entities = msp.query('CIRCLE[layer=="ISLAND"]')
    for e in island_entities:
        if abs(e.dxf.radius - 4.0) < 0.1:
            if abs(e.dxf.center.x - 100.0) < 1.0 and abs(e.dxf.center.y - 100.0) < 1.0:
                result["island_circle_found"] = True
                break

    # Check Roadway Geometry (Layer ROADWAY)
    # We expect:
    # - ARCS (radius 12) -> segments of outer ring
    # - ARCS (radius 6) -> fillets
    # - LINES -> approach legs
    # - NO CIRCLE (radius 12) -> this would mean they didn't trim
    
    roadway_entities = msp.query('*[layer=="ROADWAY"]')
    
    for e in roadway_entities:
        etype = e.dxftype()
        
        if etype == 'CIRCLE':
            if abs(e.dxf.radius - 12.0) < 0.1:
                result["outer_circle_untouched"] = True # Bad sign for this task
        
        elif etype == 'ARC':
            if abs(e.dxf.radius - 12.0) < 0.1:
                result["outer_arcs_found"] = True
            elif abs(e.dxf.radius - 6.0) < 0.5: # Slightly looser tolerance for fillets
                result["fillet_arcs_found"] = True
        
        elif etype == 'LINE':
            result["roadway_lines_found"] = True

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

# Run the analysis if file exists
if [ "$FILE_EXISTS" = "true" ]; then
    python3 /tmp/analyze_dxf.py > /tmp/dxf_analysis.json 2>/dev/null || echo "{}" > /tmp/dxf_analysis.json
else
    echo '{"valid_dxf": false, "error": "File not found"}' > /tmp/dxf_analysis.json
fi

# 4. Consolidate Result
# Read the analysis JSON content safe for embedding
ANALYSIS_CONTENT=$(cat /tmp/dxf_analysis.json)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "dxf_analysis": $ANALYSIS_CONTENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="