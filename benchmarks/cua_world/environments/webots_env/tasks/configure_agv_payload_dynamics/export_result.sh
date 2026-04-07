#!/bin/bash
echo "=== Exporting configure_agv_payload_dynamics result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Desktop/agv_heavy_payload.wbt"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

# Check output file and timestamps
if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Extract physics and configuration data via Python script
python3 -c "
import re
import json
import os

output_path = '$OUTPUT_PATH'
result = {
    'file_exists': $FILE_EXISTS,
    'file_created_during_task': $FILE_CREATED_DURING_TASK,
    'file_size': $FILE_SIZE,
    'payload_mass': None,
    'payload_com': None,
    'left_torque': None,
    'right_torque': None
}

if result['file_exists']:
    with open(output_path, 'r', errors='replace') as f:
        content = f.read()

    # Extract CUSTOM_PAYLOAD physics
    idx = content.find('DEF CUSTOM_PAYLOAD Solid')
    if idx != -1:
        chunk = content[idx:idx+2000]
        physics_m = re.search(r'physics\s+(?:DEF\s+\w+\s+)?Physics\s*\{([^}]+)\}', chunk, re.DOTALL)
        if physics_m:
            p_block = physics_m.group(1)
            # Mass
            m_match = re.search(r'mass\s+([\d.]+)', p_block)
            if m_match: result['payload_mass'] = float(m_match.group(1))
            # Center of Mass (handles optional brackets and commas)
            c_match = re.search(r'centerOfMass\s+(?:\[\s*)?([-\d.]+)\s*,?\s*([-\d.]+)\s*,?\s*([-\d.]+)', p_block)
            if c_match: result['payload_com'] = [float(c_match.group(1)), float(c_match.group(2)), float(c_match.group(3))]

    # Extract Motors
    def get_torque(name):
        # Try finding strictly DEF <name> RotationalMotor
        m1 = re.search(r'DEF\s+' + name + r'\s+RotationalMotor\s*\{([^}]+)\}', content, re.DOTALL)
        if m1:
            tm = re.search(r'maxTorque\s+([\d.]+)', m1.group(1))
            if tm: return float(tm.group(1))
        
        # Fallback: Try finding name field within any RotationalMotor
        motors = re.findall(r'RotationalMotor\s*\{([^}]+)\}', content, re.DOTALL)
        for m_block in motors:
            if re.search(r'name\s+\"' + name + r'\"', m_block):
                tm = re.search(r'maxTorque\s+([\d.]+)', m_block)
                if tm: return float(tm.group(1))
        return None

    result['left_torque'] = get_torque('left_motor')
    result['right_torque'] = get_torque('right_motor')

# Save to temp result file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="