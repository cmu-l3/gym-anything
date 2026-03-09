#!/bin/bash
# Export script for Robot Arm Kinematics task
set -o pipefail

trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "Creating fallback result..."
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "viewport_width": 0,
    "link1_valid": false,
    "link2_valid": false,
    "structure_valid": false,
    "error": "Export script failed"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Robot Arm Kinematics Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Run Python script to parse the GeoGebra file and validate geometry
python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time, math
import xml.etree.ElementTree as ET

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/robot_kinematics.ggb"
TASK_START_TIME = 0
try:
    with open("/tmp/task_start_time") as f:
        TASK_START_TIME = int(f.read().strip())
except Exception:
    pass

result = {
    "file_found": False,
    "file_path": "",
    "file_created_during_task": False,
    "viewport_width": 0,
    "points_count": 0,
    "segments_count": 0,
    "circles_count": 0,
    "base_found": False,
    "target_found": False,
    "elbow_candidates": [],
    "link1_lengths": [],
    "link2_lengths": [],
    "workspace_circle_found": False,
    "timestamp": int(time.time())
}

# Find file
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Check recent files
    candidates = sorted(
        glob.glob("/home/ga/Documents/GeoGebra/**/*.ggb", recursive=True),
        key=os.path.getmtime, reverse=True
    )
    for c in candidates:
        if TASK_START_TIME > 0 and int(os.path.getmtime(c)) >= TASK_START_TIME:
            found_file = c
            break

if found_file:
    result["file_found"] = True
    result["file_path"] = found_file
    mtime = os.path.getmtime(found_file)
    result["file_created_during_task"] = int(mtime) > TASK_START_TIME

    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                root = ET.fromstring(xml_content)
                
                # 1. Analyze Viewport (EuclidianView)
                # <euclidianView> ... <coordSystem xZero="395.0" yZero="312.0" scale="1.0" yscale="1.0"/> ... </euclidianView>
                # Actually, scale is pixels per unit. Default is usually ~50.
                # If working in mm (hundreds), scale should be small (e.g., 0.5 or 1).
                # We can also check xMin/xMax if available, or infer from scale and window size.
                view = root.find(".//euclidianView")
                if view is not None:
                    coord = view.find("coordSystem")
                    if coord is not None:
                        scale = float(coord.get("scale", "50"))
                        # Assuming 1920 width, visible width in units = 1920 / scale
                        result["viewport_width"] = 1920.0 / scale
                
                # 2. Extract Points
                points = {}
                construction = root.find(".//construction")
                if construction is not None:
                    for elem in construction.findall("element"):
                        if elem.get("type") == "point":
                            label = elem.get("label")
                            coords = elem.find("coords")
                            if coords is not None:
                                x = float(coords.get("x", 0))
                                y = float(coords.get("y", 0))
                                z = float(coords.get("z", 1))
                                if abs(z) > 1e-9:
                                    points[label] = {"x": x/z, "y": y/z, "fixed": False}
                                
                                # Check if fixed (Base)
                                if elem.find("fixed") is not None:
                                    points[label]["fixed"] = True
                    
                    # 3. Analyze Geometry
                    result["points_count"] = len(points)
                    
                    # Identify Base (near 0,0)
                    base_labels = []
                    for label, p in points.items():
                        if abs(p["x"]) < 1.0 and abs(p["y"]) < 1.0:
                            result["base_found"] = True
                            base_labels.append(label)
                    
                    # Identify Potential Target (Free point, far from origin)
                    target_labels = []
                    for label, p in points.items():
                        dist = math.sqrt(p["x"]**2 + p["y"]**2)
                        # Heuristic: Target should be roughly reachable (0 to 600) but not the base
                        if dist > 10 and not p.get("fixed", False):
                            # Check if it's a free point (not an intersection)
                            # In XML, dependent points usually don't have <element type="point"> as primary definition without command
                            # We'll treat all non-base points as candidates for now
                            target_labels.append(label)
                            
                    if target_labels:
                        result["target_found"] = True

                    # 4. Check Links (Distance between points)
                    # We are looking for a chain Base -> Elbow -> Target
                    # Link 1 = 290, Link 2 = 302
                    
                    for b_lbl in base_labels:
                        base = points[b_lbl]
                        for t_lbl in target_labels:
                            target = points[t_lbl]
                            
                            # Look for an Elbow point
                            for e_lbl, elbow in points.items():
                                if e_lbl == b_lbl or e_lbl == t_lbl:
                                    continue
                                
                                d1 = math.sqrt((elbow["x"] - base["x"])**2 + (elbow["y"] - base["y"])**2)
                                d2 = math.sqrt((elbow["x"] - target["x"])**2 + (elbow["y"] - target["y"])**2)
                                
                                # Check if lengths match tolerance (±1mm)
                                if abs(d1 - 290) < 5:
                                    result["link1_lengths"].append(d1)
                                if abs(d2 - 302) < 5:
                                    result["link2_lengths"].append(d2)
                                    
                                if abs(d1 - 290) < 5 and abs(d2 - 302) < 5:
                                    result["elbow_candidates"].append({
                                        "base": b_lbl,
                                        "elbow": e_lbl,
                                        "target": t_lbl,
                                        "l1": d1,
                                        "l2": d2
                                    })

                # 5. Check for Workspace Boundary Circle (Radius ~592)
                # <element type="conic"> or <command name="Circle">
                # We can just check radius values of circles
                # GeoGebra stores circles as matrix or command. 
                # Easier to check "Circle" commands and their arguments, or just regex the XML for 592
                if "592" in xml_content:
                    result["workspace_circle_found"] = True
                
                # Also count generic elements
                result["segments_count"] = len(re.findall(r'<element type="segment"', xml_content))
                result["circles_count"] = len(re.findall(r'<element type="conic"', xml_content))

    except Exception as e:
        result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete."
cat /tmp/task_result.json