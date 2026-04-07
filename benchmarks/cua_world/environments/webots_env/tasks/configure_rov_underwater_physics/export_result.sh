#!/bin/bash
# Export script for configure_rov_underwater_physics task
# Checks if the agent saved the configured world and extracts physics values.

echo "=== Exporting configure_rov_underwater_physics result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

OUTPUT_FILE="/home/ga/Desktop/rov_configured.wbt"
START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
RESULT_JSON="/tmp/configure_rov_underwater_physics_result.json"

# Python script to safely parse the Webots VRML file and extract all metrics
python3 - << PYEOF > "$RESULT_JSON"
import json
import os
import re
import sys

output_path = "$OUTPUT_FILE"
start_time = int("$START_TIME")

result = {
    "file_exists": False,
    "file_size": 0,
    "file_mtime": 0,
    "task_start_time": start_time,
    "density": -1.0,
    "mass": -1.0,
    "has_damping": False,
    "linear": -1.0,
    "angular": -1.0,
    "gravity": -1.0,
    "error": None
}

if os.path.exists(output_path):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_path)
    result["file_mtime"] = int(os.path.getmtime(output_path))
    
    try:
        with open(output_path, "r", errors="replace") as f:
            content = f.read()

        # Gravity (WorldInfo)
        m_grav = re.search(r'WorldInfo\s*\{[^{}]*gravity\s+([\d.]+)', content)
        if m_grav:
            result["gravity"] = float(m_grav.group(1))

        # Fluid Density
        m_fluid = re.search(r'Fluid\s*\{[^}]*density\s+([\d.]+)', content)
        if m_fluid:
            result["density"] = float(m_fluid.group(1))

        # ROV Robot Mass & Damping
        idx = content.find('DEF ROV_VEHICLE Robot')
        if idx != -1:
            robot_chunk = content[idx:idx+2500]
            m_mass = re.search(r'physics\s+Physics\s*\{[^}]*mass\s+([\d.]+)', robot_chunk)
            if m_mass:
                result["mass"] = float(m_mass.group(1))

            damping_idx = robot_chunk.find('Damping')
            if damping_idx != -1:
                result["has_damping"] = True
                damping_chunk = robot_chunk[damping_idx:damping_idx+200]
                m_lin = re.search(r'linear\s+([\d.]+)', damping_chunk)
                m_ang = re.search(r'angular\s+([\d.]+)', damping_chunk)
                if m_lin: result["linear"] = float(m_lin.group(1))
                if m_ang: result["angular"] = float(m_ang.group(1))
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

echo "Result JSON written to $RESULT_JSON"
cat "$RESULT_JSON"

echo "=== Export Complete ==="