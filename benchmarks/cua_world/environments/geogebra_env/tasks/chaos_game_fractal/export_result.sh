#!/bin/bash
# Export script for Chaos Game Fractal task
set -o pipefail

# Ensure fallback result
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "vertices_found": 0,
    "total_points_generated": 0,
    "fraction_inside_triangle": 0.0,
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

echo "=== Exporting Chaos Game Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Run Python script to analyze the .ggb file structure and geometry
python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time
import xml.etree.ElementTree as ET
import numpy as np

# Configuration
EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/chaos_europe.ggb"
VERTICES_TARGET = {
    "London": (-0.1, 51.5),
    "Paris": (2.3, 48.9),
    "Brussels": (4.3, 50.8)
}
TOLERANCE = 0.5  # degrees Lat/Long

# Get task start time
TASK_START_TIME = 0
try:
    with open("/tmp/task_start_time") as f:
        TASK_START_TIME = int(f.read().strip())
except Exception:
    pass

result = {
    "file_found": False,
    "file_path": "",
    "file_size": 0,
    "file_modified": 0,
    "file_created_during_task": False,
    "vertices_found": 0,
    "vertex_details": {},
    "total_points_generated": 0,
    "fraction_inside_triangle": 0.0,
    "method_detected": "unknown"
}

# 1. Locate File
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Search for any recent .ggb file
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
    result["file_size"] = os.path.getsize(found_file)
    mtime = os.path.getmtime(found_file)
    result["file_modified"] = int(mtime)
    result["file_created_during_task"] = int(mtime) > TASK_START_TIME

    # 2. Analyze XML Content
    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # A. Check Vertices
                # Parse XML to find points
                root = ET.fromstring(xml_content)
                construction = root.find('.//construction')
                
                all_points = []
                
                if construction is not None:
                    for elem in construction.findall('element'):
                        if elem.get('type') == 'point':
                            coords = elem.find('coords')
                            if coords is not None:
                                try:
                                    x = float(coords.get('x', 0))
                                    y = float(coords.get('y', 0))
                                    z_coord = float(coords.get('z', 1))
                                    if abs(z_coord) > 1e-9:
                                        all_points.append((x/z_coord, y/z_coord))
                                except ValueError:
                                    pass

                # Check if specific vertices exist
                found_verts = 0
                found_details = {}
                found_vertex_coords = []
                
                for city, (tx, ty) in VERTICES_TARGET.items():
                    # Find closest point
                    best_dist = float('inf')
                    best_pt = None
                    for (px, py) in all_points:
                        dist = ((px - tx)**2 + (py - ty)**2)**0.5
                        if dist < best_dist:
                            best_dist = dist
                            best_pt = (px, py)
                    
                    if best_dist < TOLERANCE:
                        found_verts += 1
                        found_details[city] = {"found": True, "coords": best_pt, "error": best_dist}
                        found_vertex_coords.append(best_pt)
                    else:
                        found_details[city] = {"found": False, "closest_dist": best_dist}

                result["vertices_found"] = found_verts
                result["vertex_details"] = found_details

                # B. Check Data Volume (Fractal Points)
                # Count points in spreadsheet lists or generated sequences
                # Spreadsheets often store points as independent elements <element type="point" label="E1">
                # Sequences store as one element producing many points
                
                point_count = len(all_points)
                result["total_points_generated"] = point_count
                
                # If using Sequence command, we might have fewer 'element' tags but a command generating a list
                # Check for Sequence command output
                list_elements = construction.findall(".//element[@type='list']")
                for lst in list_elements:
                    # Try to estimate list size from value attribute or command
                    # This is tricky in XML, but we can look for large lists
                    pass

                # C. Geometric Validity (Chaos Game Property)
                # If we found the 3 vertices, check if other points are inside the triangle
                if len(found_vertex_coords) == 3 and len(all_points) > 20:
                    A = np.array(found_vertex_coords[0])
                    B = np.array(found_vertex_coords[1])
                    C = np.array(found_vertex_coords[2])
                    
                    # Barycentric coordinate check
                    # P = uA + vB + wC, u+v+w=1. P inside if 0<=u,v,w<=1
                    
                    # Vectors
                    v0 = C - A
                    v1 = B - A
                    
                    inside_count = 0
                    test_sample_size = 0
                    
                    # Dot products for barycentric calc
                    dot00 = np.dot(v0, v0)
                    dot01 = np.dot(v0, v1)
                    dot11 = np.dot(v1, v1)
                    invDenom = 1 / (dot00 * dot11 - dot01 * dot01 + 1e-9)

                    for P_tuple in all_points:
                        P = np.array(P_tuple)
                        # Skip if P is one of the vertices
                        if any(np.linalg.norm(P - v) < 0.01 for v in [A, B, C]):
                            continue
                            
                        v2 = P - A
                        dot02 = np.dot(v0, v2)
                        dot12 = np.dot(v1, v2)
                        
                        u = (dot11 * dot02 - dot01 * dot12) * invDenom
                        v = (dot00 * dot12 - dot01 * dot02) * invDenom
                        
                        test_sample_size += 1
                        if (u >= -0.01) and (v >= -0.01) and (u + v <= 1.01):
                            inside_count += 1
                            
                    if test_sample_size > 0:
                        result["fraction_inside_triangle"] = inside_count / test_sample_size
                
    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export Complete ==="