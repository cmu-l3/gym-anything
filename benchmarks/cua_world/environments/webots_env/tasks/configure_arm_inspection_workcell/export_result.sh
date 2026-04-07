#!/bin/bash
echo "=== Exporting configure_arm_inspection_workcell result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

OUTPUT_FILE="/home/ga/Desktop/inspection_workcell.wbt"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
ROBOT_TX="not_found"
ROBOT_TY="not_found"
ROBOT_TZ="not_found"
CAM_WIDTH="not_found"
CAM_HEIGHT="not_found"
CAM_FOV="not_found"
MOTOR_VEL="not_found"
TIMESTEP="not_found"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(get_file_size "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    echo "Output file found: $OUTPUT_FILE ($FILE_SIZE bytes)"

    # Use Python to extract all the required field values from the saved .wbt file
    python3 << 'PYEOF' > /tmp/wbt_parsed_values.txt
import re, sys

output_file = "/home/ga/Desktop/inspection_workcell.wbt"
try:
    with open(output_file, 'r', errors='replace') as f:
        content = f.read()
except Exception as e:
    print(f"ERROR={e}")
    sys.exit(0)

# Extract WorldInfo basicTimeStep
m_ts = re.search(r'basicTimeStep\s+([\d.]+)', content)
print(f"TIMESTEP={m_ts.group(1) if m_ts else 'not_found'}")

# Extract INSPECTION_ARM translation
idx_arm = content.find('DEF INSPECTION_ARM Robot')
if idx_arm != -1:
    segment = content[idx_arm:idx_arm+300]
    m_trans = re.search(r'translation\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)', segment)
    if m_trans:
        print(f"ROBOT_TX={m_trans.group(1)}")
        print(f"ROBOT_TY={m_trans.group(2)}")
        print(f"ROBOT_TZ={m_trans.group(3)}")
    else:
        print("ROBOT_TX=not_found\nROBOT_TY=not_found\nROBOT_TZ=not_found")
else:
    print("ROBOT_TX=not_found\nROBOT_TY=not_found\nROBOT_TZ=not_found")

# Extract inspection_camera properties
idx_cam = content.find('DEF inspection_camera Camera')
if idx_cam == -1:
    idx_cam = content.find('Camera {') # Fallback to any camera

if idx_cam != -1:
    segment = content[idx_cam:idx_cam+300]
    m_w = re.search(r'width\s+(\d+)', segment)
    m_h = re.search(r'height\s+(\d+)', segment)
    m_fov = re.search(r'fieldOfView\s+([\d.]+)', segment)
    print(f"CAM_WIDTH={m_w.group(1) if m_w else 'not_found'}")
    print(f"CAM_HEIGHT={m_h.group(1) if m_h else 'not_found'}")
    print(f"CAM_FOV={m_fov.group(1) if m_fov else 'not_found'}")
else:
    print("CAM_WIDTH=not_found\nCAM_HEIGHT=not_found\nCAM_FOV=not_found")

# Extract shoulder_motor properties
idx_motor = content.find('DEF shoulder_motor RotationalMotor')
if idx_motor == -1:
    idx_motor = content.find('RotationalMotor {')

if idx_motor != -1:
    segment = content[idx_motor:idx_motor+300]
    m_vel = re.search(r'maxVelocity\s+([\d.]+)', segment)
    print(f"MOTOR_VEL={m_vel.group(1) if m_vel else 'not_found'}")
else:
    print("MOTOR_VEL=not_found")
PYEOF

    # Source the parsed variables
    if [ -f /tmp/wbt_parsed_values.txt ]; then
        source /tmp/wbt_parsed_values.txt
    fi
    
    echo "  Robot TX: $ROBOT_TX"
    echo "  Camera: $CAM_WIDTH x $CAM_HEIGHT (FOV: $CAM_FOV)"
    echo "  Motor maxVelocity: $MOTOR_VEL"
    echo "  Timestep: $TIMESTEP"
else
    echo "Output file NOT found at: $OUTPUT_FILE"
fi

# Write result JSON cleanly
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_path": "$OUTPUT_FILE",
    "robot_tx": "${ROBOT_TX:-not_found}",
    "robot_ty": "${ROBOT_TY:-not_found}",
    "robot_tz": "${ROBOT_TZ:-not_found}",
    "camera_width": "${CAM_WIDTH:-not_found}",
    "camera_height": "${CAM_HEIGHT:-not_found}",
    "camera_fov": "${CAM_FOV:-not_found}",
    "motor_velocity": "${MOTOR_VEL:-not_found}",
    "timestep": "${TIMESTEP:-not_found}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="