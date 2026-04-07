#!/bin/bash
# Export script for configure_amr_power_sim task
# Extracts configuration values from the saved Webots world file.

echo "=== Exporting configure_amr_power_sim result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

OUTPUT_FILE="/home/ga/Desktop/amr_power_sim.wbt"

# Execute a Python script to robustly parse the Webots format file
cat > /tmp/parse_amr_world.py << 'EOF'
import re
import json
import sys
import os

output_file = "/home/ga/Desktop/amr_power_sim.wbt"

result = {
    "file_exists": False,
    "file_size": 0,
    "battery": [],
    "cpuConsumption": 0.0,
    "left_motor_consumption": 0.0,
    "right_motor_consumption": 0.0,
}

if os.path.exists(output_file):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_file)
    
    with open(output_file, 'r', errors='replace') as f:
        content = f.read()
        
        # 1. Parse Battery list
        # Matches: battery [ 1800000 1800000 2000 ] or battery [1800000, 1800000, 2000]
        batt_match = re.search(r'battery\s*\[(.*?)\]', content)
        if batt_match:
            nums = re.findall(r'[\d.]+', batt_match.group(1))
            result["battery"] = [float(n) for n in nums]
            
        # 2. Parse CPU Consumption
        cpu_match = re.search(r'cpuConsumption\s+([\d.]+)', content)
        if cpu_match:
            result["cpuConsumption"] = float(cpu_match.group(1))
            
        # 3. Parse Left Motor Consumption Factor
        # Can appear before or after the name field within the RotationalMotor block
        left_match = re.search(r'name\s+"left_wheel_motor"[^}]*?consumptionFactor\s+([\d.]+)', content, re.DOTALL)
        if not left_match:
            left_match = re.search(r'consumptionFactor\s+([\d.]+)[^}]*?name\s+"left_wheel_motor"', content, re.DOTALL)
        if left_match:
            result["left_motor_consumption"] = float(left_match.group(1))
            
        # 4. Parse Right Motor Consumption Factor
        right_match = re.search(r'name\s+"right_wheel_motor"[^}]*?consumptionFactor\s+([\d.]+)', content, re.DOTALL)
        if not right_match:
            right_match = re.search(r'consumptionFactor\s+([\d.]+)[^}]*?name\s+"right_wheel_motor"', content, re.DOTALL)
        if right_match:
            result["right_motor_consumption"] = float(right_match.group(1))

# Also add timestamps
try:
    with open('/tmp/task_start_timestamp', 'r') as f:
        result['task_start_timestamp'] = int(f.read().strip())
except Exception:
    result['task_start_timestamp'] = 0
    
if result["file_exists"]:
    result['file_mtime'] = int(os.path.getmtime(output_file))
else:
    result['file_mtime'] = 0

with open('/tmp/amr_power_sim_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

python3 /tmp/parse_amr_world.py

echo "Result JSON extracted:"
cat /tmp/amr_power_sim_result.json

echo "=== Export Complete ==="