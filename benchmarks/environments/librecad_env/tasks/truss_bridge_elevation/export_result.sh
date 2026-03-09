#!/bin/bash
set -e
echo "=== Exporting truss_bridge_elevation results ==="

# Source utilities not available, so we implement inline checks
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DXF_PATH="/home/ga/Documents/LibreCAD/truss_elevation.dxf"

# 1. Capture final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check file existence and timestamps
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$DXF_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$DXF_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$DXF_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Create Python analysis script to run INSIDE the container
# We do this because the host might not have ezdxf, but the container does.
cat << 'EOF' > /tmp/analyze_truss.py
import sys
import json
import math
import os

try:
    import ezdxf
except ImportError:
    print(json.dumps({"error": "ezdxf not installed"}))
    sys.exit(0)

def analyze_dxf(path):
    results = {
        "valid_dxf": False,
        "layers": [],
        "entities": {
            "lines": 0,
            "circles": 0,
            "dimensions": 0,
            "texts": 0
        },
        "geometry": {
            "bottom_chord": False,
            "top_chord": False,
            "vertical_ends": 0,
            "diagonals": 0,
            "supports": 0
        },
        "content": {
            "has_title": False,
            "has_scale": False,
            "has_pin_label": False,
            "has_roller_label": False
        }
    }

    if not os.path.exists(path):
        return results

    try:
        doc = ezdxf.readfile(path)
        msp = doc.modelspace()
        results["valid_dxf"] = True
    except Exception as e:
        results["error"] = str(e)
        return results

    # Check Layers
    results["layers"] = [layer.dxf.name.lower() for layer in doc.layers]

    # Helper for geometry checks
    lines = []
    texts = []
    
    for e in msp:
        dtype = e.dxftype()
        if dtype == "LINE":
            results["entities"]["lines"] += 1
            lines.append({
                "start": (e.dxf.start.x, e.dxf.start.y),
                "end": (e.dxf.end.x, e.dxf.end.y),
                "layer": e.dxf.layer.lower()
            })
        elif dtype == "CIRCLE":
            results["entities"]["circles"] += 1
        elif dtype in ["DIMENSION", "ARC_DIMENSION", "LARGE_RADIAL_DIMENSION"]:
            results["entities"]["dimensions"] += 1
        elif dtype in ["TEXT", "MTEXT"]:
            results["entities"]["texts"] += 1
            # Extract text content
            content = e.dxf.text if dtype == "TEXT" else e.text
            texts.append(content.upper())

    # Analyze Geometry (Tolerance 100mm)
    TOL = 100.0
    
    def is_horiz(l, y_val, min_len):
        y1, y2 = l["start"][1], l["end"][1]
        x_span = abs(l["start"][0] - l["end"][0])
        return abs(y1 - y_val) < TOL and abs(y2 - y_val) < TOL and x_span > min_len

    def is_vert(l, x_val, min_len):
        x1, x2 = l["start"][0], l["end"][0]
        y_span = abs(l["start"][1] - l["end"][1])
        return abs(x1 - x_val) < TOL and abs(x2 - x_val) < TOL and y_span > min_len
    
    # Check Chords
    for l in lines:
        if is_horiz(l, 0, 11000):
            results["geometry"]["bottom_chord"] = True
        if is_horiz(l, 2000, 11000):
            results["geometry"]["top_chord"] = True
        if is_vert(l, 0, 1500):
            results["geometry"]["vertical_ends"] += 1
        if is_vert(l, 12000, 1500):
            results["geometry"]["vertical_ends"] += 1

    # Check Diagonals (approximate check of slope/endpoints)
    # Expected diagonals connect (0,0)->(2000,2000), etc.
    # Just counting substantial non-orthogonal lines
    for l in lines:
        dx = abs(l["start"][0] - l["end"][0])
        dy = abs(l["start"][1] - l["end"][1])
        if dx > 100 and dy > 100: # It is diagonal
            results["geometry"]["diagonals"] += 1

    # Check Text Content
    full_text = " ".join(texts)
    results["content"]["has_title"] = "WARREN" in full_text
    results["content"]["has_scale"] = "1:100" in full_text or "SCALE" in full_text
    results["content"]["has_pin_label"] = "PIN" in full_text
    results["content"]["has_roller_label"] = "ROLLER" in full_text

    return results

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(json.dumps(analyze_dxf(sys.argv[1])))
    else:
        print(json.dumps({}))
EOF

# 4. Run the analysis script if file exists
if [ "$FILE_EXISTS" = "true" ]; then
    echo "Running DXF analysis..."
    python3 /tmp/analyze_truss.py "$DXF_PATH" > /tmp/truss_analysis.json
else
    echo "{}" > /tmp/truss_analysis.json
fi

# 5. Assemble final result JSON
cat << EOF > /tmp/task_result.json
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "analysis": $(cat /tmp/truss_analysis.json)
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json