#!/bin/bash
# Export script for Rugby Kick Optimization task
set -o pipefail

# Ensure fallback result
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_path": "",
    "file_created_during_task": false,
    "has_goal_width": false,
    "has_try_offset": false,
    "has_angle_measure": false,
    "has_function": false,
    "optimal_point_found": false,
    "error": "Export script failed"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

# Utilities
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Rugby Optimization Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Run Python analysis
python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time, math

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/rugby_optimization.ggb"
TASK_START_TIME = 0
try:
    with open("/tmp/task_start_time") as f:
        TASK_START_TIME = int(f.read().strip())
except:
    pass

result = {
    "file_found": False,
    "file_path": "",
    "file_size": 0,
    "file_modified": 0,
    "file_created_during_task": False,
    "task_start_time": TASK_START_TIME,
    "has_goal_width": False,
    "has_try_offset": False,
    "has_angle_measure": False,
    "has_function": False,
    "optimal_point_found": False,
    "optimal_value_x": None,
    "xml_commands": []
}

# 1. Find File
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
    result["file_size"] = os.path.getsize(found_file)
    mtime = int(os.path.getmtime(found_file))
    result["file_modified"] = mtime
    result["file_created_during_task"] = mtime > TASK_START_TIME

    # 2. Parse XML
    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # Extract commands for verification
                commands = re.findall(r'<command name="([^"]+)"', xml_content)
                result["xml_commands"] = list(set(commands))

                # Check for angle measurement (Angle command or element)
                has_angle_cmd = bool(re.search(r'<command name="Angle"', xml_content, re.IGNORECASE))
                has_angle_elem = bool(re.search(r'<element type="angle"', xml_content, re.IGNORECASE))
                result["has_angle_measure"] = has_angle_cmd or has_angle_elem

                # Check for Function (graphing the angle)
                # Look for atan (arctangent) which is typical for this problem
                # or general function definition
                has_func_elem = bool(re.search(r'<element type="function"', xml_content, re.IGNORECASE))
                has_atan = bool(re.search(r'atan|arctan', xml_content, re.IGNORECASE))
                result["has_function"] = has_func_elem

                # 3. Geometric Verification (Robust to coordinate system choice)
                # We need to find two points 5.6 units apart (Goal)
                # And a reference point 10 units from one of them (Try)
                
                import xml.etree.ElementTree as ET
                root = ET.fromstring(xml_content)
                
                points = []
                for elem in root.findall('.//element'):
                    if elem.get('type') == 'point':
                        coords = elem.find('coords')
                        if coords is not None:
                            try:
                                x = float(coords.get('x', 0))
                                y = float(coords.get('y', 0))
                                z = float(coords.get('z', 1))
                                if abs(z) > 1e-9:
                                    points.append((x/z, y/z))
                            except:
                                pass
                
                # Check distances between points
                found_5_6 = False
                found_10_0 = False
                
                for i in range(len(points)):
                    for j in range(i+1, len(points)):
                        dist = math.sqrt((points[i][0]-points[j][0])**2 + (points[i][1]-points[j][1])**2)
                        
                        # Check goal width (5.6m)
                        if abs(dist - 5.6) < 0.1:
                            found_5_6 = True
                            
                        # Check try offset (10m)
                        if abs(dist - 10.0) < 0.1:
                            found_10_0 = True
                
                result["has_goal_width"] = found_5_6
                result["has_try_offset"] = found_10_0

                # 4. Optimal Point Verification
                # Theoretical optimum is sqrt(10 * 15.6) = 12.49
                # Check if any point exists with a coordinate close to 12.49 or -12.49
                # This could be x-coord on a graph, or y-coord (distance)
                
                optimal_target = 12.49
                for p in points:
                    if (abs(abs(p[0]) - optimal_target) < 0.5) or (abs(abs(p[1]) - optimal_target) < 0.5):
                        result["optimal_point_found"] = True
                        result["optimal_value_x"] = p[0] if abs(abs(p[0]) - optimal_target) < 0.5 else p[1]
                        break
                        
                # Also check Extremum command output
                if not result["optimal_point_found"]:
                    if re.search(r'<command name="Extremum"', xml_content, re.IGNORECASE):
                        # If they used Extremum command, give benefit of doubt if function exists
                        if result["has_function"]:
                            result["optimal_point_found"] = True

    except Exception as e:
        result["error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export Complete ==="