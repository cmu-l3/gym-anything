#!/bin/bash
echo "=== Setting up compose_graph_with_function task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Verify the target metric has data
echo "Checking for target metric data: servers.ec2_instance_1.cpu.utilization"
DATA_CHECK=$(graphite_query "servers.ec2_instance_1.cpu.utilization" "-24h" "json")
if echo "$DATA_CHECK" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    points = [p for p in data[0]['datapoints'] if p[0] is not None]
    print(f'Found {len(points)} non-null data points')
    sys.exit(0 if len(points) > 0 else 1)
except:
    sys.exit(1)
" 2>/dev/null; then
    echo "Target metric has data"
else
    echo "WARNING: Target metric may not have data yet"
fi

# Record initial state
date +%s > /tmp/task_start_time

# Navigate Firefox to the Graphite Composer
focus_firefox
navigate_firefox_to "http://localhost/composer"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== compose_graph_with_function task setup complete ==="
echo "Agent should: Add metric, apply movingAverage function with window=10"
