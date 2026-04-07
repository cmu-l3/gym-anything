#!/bin/bash
# Export script for optimize_swarm_performance task

echo "=== Exporting optimize_swarm_performance result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

OUTPUT_FILE="/home/ga/Desktop/optimized_training_env.wbt"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
CREATED_DURING_TASK="false"
BASIC_TIMESTEP="not_found"
THREAD_COUNT="not_found"
FPS_VALUE="not_found"
CAST_SHADOWS="not_found"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(get_file_size "$OUTPUT_FILE")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
    
    echo "Output file found: $OUTPUT_FILE ($FILE_SIZE bytes)"

    # Use python to extract the values via regex safely
    python3 -c "
import re

with open('$OUTPUT_FILE') as f:
    content = f.read()

# Extract basicTimeStep
m_ts = re.search(r'basicTimeStep\s+(\d+)', content)
print('BASIC_TIMESTEP=' + (m_ts.group(1) if m_ts else 'not_found'))

# Extract optimalThreadCount
m_threads = re.search(r'optimalThreadCount\s+(\d+)', content)
print('THREAD_COUNT=' + (m_threads.group(1) if m_threads else 'not_found'))

# Extract FPS
m_fps = re.search(r'FPS\s+([\d.]+)', content)
print('FPS_VALUE=' + (m_fps.group(1) if m_fps else 'not_found'))

# Extract castShadows from DirectionalLight
# Pattern matches DirectionalLight { ... castShadows TRUE/FALSE ... }
dl_idx = content.find('DirectionalLight')
if dl_idx != -1:
    dl_segment = content[dl_idx:dl_idx+500]
    m_shadows = re.search(r'castShadows\s+(TRUE|FALSE)', dl_segment)
    if m_shadows:
        print('CAST_SHADOWS=' + m_shadows.group(1))
    else:
        # Default in webots if not explicitly stated could vary, but usually TRUE if absent and we started with TRUE
        print('CAST_SHADOWS=not_found')
else:
    print('CAST_SHADOWS=no_light_node_found')
" > /tmp/swarm_performance_analysis.txt 2>/dev/null

    # Load into bash variables
    BASIC_TIMESTEP=$(grep "^BASIC_TIMESTEP=" /tmp/swarm_performance_analysis.txt | cut -d'=' -f2)
    THREAD_COUNT=$(grep "^THREAD_COUNT=" /tmp/swarm_performance_analysis.txt | cut -d'=' -f2)
    FPS_VALUE=$(grep "^FPS_VALUE=" /tmp/swarm_performance_analysis.txt | cut -d'=' -f2)
    CAST_SHADOWS=$(grep "^CAST_SHADOWS=" /tmp/swarm_performance_analysis.txt | cut -d'=' -f2)

    echo "  basicTimeStep: $BASIC_TIMESTEP"
    echo "  optimalThreadCount: $THREAD_COUNT"
    echo "  FPS: $FPS_VALUE"
    echo "  castShadows: $CAST_SHADOWS"
else
    echo "Output file NOT found at: $OUTPUT_FILE"
fi

# Write result JSON
cat > /tmp/optimize_swarm_performance_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "output_path": "$OUTPUT_FILE",
    "basic_timestep": "${BASIC_TIMESTEP}",
    "thread_count": "${THREAD_COUNT}",
    "fps_value": "${FPS_VALUE}",
    "cast_shadows": "${CAST_SHADOWS}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON written to /tmp/optimize_swarm_performance_result.json"
cat /tmp/optimize_swarm_performance_result.json

echo "=== Export Complete ==="