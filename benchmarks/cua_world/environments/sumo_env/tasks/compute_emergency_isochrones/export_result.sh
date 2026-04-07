#!/bin/bash
echo "=== Exporting compute_emergency_isochrones result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

OUTPUT_DIR="/home/ga/SUMO_Output"
AGENT_SUMMARY="$OUTPUT_DIR/isochrone_summary.txt"
AGENT_SELECTION="$OUTPUT_DIR/isochrone_selection.txt"

# 1. Compute Ground Truth using Python inside the container
echo "Computing Ground Truth..."
cat > /tmp/calc_gt.py << 'EOF'
import sys, json, os, heapq

# Ensure sumolib is in path
if 'SUMO_HOME' in os.environ:
    sys.path.append(os.path.join(os.environ['SUMO_HOME'], 'tools'))
else:
    sys.path.append('/usr/share/sumo/tools')
import sumolib

net_path = '/home/ga/SUMO_Scenarios/bologna_acosta/acosta_buslanes.net.xml'
gt_data = {}

try:
    net = sumolib.net.readNet(net_path)
    
    # Identify start edge
    valid_edges = []
    for e in net.getEdges():
        if e.getFunction() != 'internal' and len(e.getOutgoing()) > 0:
            valid_edges.append(e)
            
    # Sort by length descending, then ID ascending (alphabetically)
    valid_edges.sort(key=lambda x: (-x.getLength(), x.getID()))
    start_edge = valid_edges[0]
    
    # Calculate Isochrone
    start_id = start_edge.getID()
    start_time = start_edge.getLength() / start_edge.getSpeed()
    
    queue = [(start_time, start_id)]
    visited_times = {start_id: start_time}
    
    while queue:
        current_time, current_id = heapq.heappop(queue)
        if current_time > visited_times.get(current_id, float('inf')):
            continue
            
        current_edge = net.getEdge(current_id)
        for out_edge in current_edge.getOutgoing().keys():
            if out_edge.getFunction() == 'internal':
                continue
                
            out_id = out_edge.getID()
            travel_time = out_edge.getLength() / out_edge.getSpeed()
            new_time = current_time + travel_time
            
            if new_time <= 120.0 and new_time < visited_times.get(out_id, float('inf')):
                visited_times[out_id] = new_time
                heapq.heappush(queue, (new_time, out_id))
                
    gt_data = {
        "success": True,
        "start_edge": start_id,
        "reachable": list(visited_times.keys())
    }
except Exception as e:
    gt_data = {
        "success": False,
        "error": str(e)
    }

with open('/tmp/gt_data.json', 'w') as f:
    json.dump(gt_data, f)
EOF

python3 /tmp/calc_gt.py
GT_DATA=$(cat /tmp/gt_data.json 2>/dev/null || echo '{"success": false, "error": "Script failed to execute"}')
rm -f /tmp/calc_gt.py /tmp/gt_data.json

# 2. Extract Agent's outputs
FILE_CREATED="false"
SUMMARY_EXISTS="false"
SELECTION_EXISTS="false"
AGENT_SUMMARY_LINES="[]"
AGENT_SELECTION_LINES="[]"

if [ -f "$AGENT_SUMMARY" ] && [ -f "$AGENT_SELECTION" ]; then
    SUMMARY_EXISTS="true"
    SELECTION_EXISTS="true"
    
    # Check if files were created during the task
    MOD_TIME=$(stat -c %Y "$AGENT_SELECTION" 2>/dev/null || echo "0")
    if [ "$MOD_TIME" -gt "$TASK_START" ]; then
        FILE_CREATED="true"
    fi
    
    # Parse files to JSON arrays safely
    AGENT_SUMMARY_LINES=$(python3 -c "import json, sys; print(json.dumps([l.strip() for l in sys.stdin.readlines()]))" < "$AGENT_SUMMARY")
    AGENT_SELECTION_LINES=$(python3 -c "import json, sys; print(json.dumps([l.strip() for l in sys.stdin.readlines() if l.strip()]))" < "$AGENT_SELECTION")
elif [ -f "$AGENT_SUMMARY" ]; then
    SUMMARY_EXISTS="true"
    AGENT_SUMMARY_LINES=$(python3 -c "import json, sys; print(json.dumps([l.strip() for l in sys.stdin.readlines()]))" < "$AGENT_SUMMARY")
elif [ -f "$AGENT_SELECTION" ]; then
    SELECTION_EXISTS="true"
    AGENT_SELECTION_LINES=$(python3 -c "import json, sys; print(json.dumps([l.strip() for l in sys.stdin.readlines() if l.strip()]))" < "$AGENT_SELECTION")
fi

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_created_during_task": $FILE_CREATED,
    "summary_exists": $SUMMARY_EXISTS,
    "selection_exists": $SELECTION_EXISTS,
    "summary_lines": $AGENT_SUMMARY_LINES,
    "selection_lines": $AGENT_SELECTION_LINES,
    "gt_data": $GT_DATA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="