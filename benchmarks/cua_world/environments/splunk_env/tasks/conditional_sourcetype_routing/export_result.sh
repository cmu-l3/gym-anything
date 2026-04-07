#!/bin/bash
echo "=== Exporting Conditional Sourcetype Routing Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot /tmp/task_final.png 2>/dev/null || true

# 1. Determine if Splunk is running
SPLUNK_RUNNING="false"
if /opt/splunk/bin/splunk status 2>/dev/null | grep -q "splunkd is running"; then
    SPLUNK_RUNNING="true"
fi

# 2. Generate a random evaluation ID
TEST_ID="EVAL_$(date +%s)_$RANDOM"
echo "Generated verification payload ID: $TEST_ID"

# 3. Create a python script to inject UDP events
cat > /tmp/inject_udp.py << 'PYEOF'
import socket
import sys
import time

test_id = sys.argv[1]
port = int(sys.argv[2])

events = [
    f"{test_id} [INFO] Routine application startup complete",
    f"{test_id} [CRITICAL] Database connection severed unexpectedly",
    f"{test_id} [WARN] CPU utilization running at 85 percent"
]

try:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    for ev in events:
        sock.sendto((ev + "\n").encode('utf-8'), ("127.0.0.1", port))
    sock.close()
    print("Events injected successfully")
except Exception as e:
    print(f"Failed to inject events: {e}")
PYEOF

# 4. Inject events to port 5140 (only if Splunk is running)
if [ "$SPLUNK_RUNNING" = "true" ]; then
    echo "Injecting verification payloads to UDP:5140..."
    python3 /tmp/inject_udp.py "$TEST_ID" 5140
    
    # Wait for Splunk to index the events
    echo "Waiting 15 seconds for Splunk ingestion pipeline..."
    sleep 15
    
    # 5. Search for the injected events via REST API
    echo "Querying Splunk for ingested payloads..."
    SEARCH_QUERY="search index=* \"$TEST_ID\" | table _raw, index, sourcetype"
    
    curl -sk -u "admin:SplunkAdmin1!" \
        "https://localhost:8089/services/search/jobs" \
        -d search="$SEARCH_QUERY" \
        -d exec_mode=oneshot \
        -d output_mode=json > /tmp/search_result.json 2>/dev/null || echo "{}" > /tmp/search_result.json
else
    echo "Splunk is not running. Skipping event injection."
    echo "{}" > /tmp/search_result.json
fi

# 6. Capture raw configuration files as a fallback
cat > /tmp/capture_configs.py << 'PYEOF'
import json
import os

configs = {"inputs": "", "props": "", "transforms": ""}
base_dir = "/opt/splunk/etc/system/local"

for conf in ["inputs.conf", "props.conf", "transforms.conf"]:
    path = os.path.join(base_dir, conf)
    if os.path.exists(path):
        try:
            with open(path, "r") as f:
                configs[conf.replace(".conf", "")] = f.read()
        except:
            pass

with open("/tmp/configs.json", "w") as f:
    json.dump(configs, f)
PYEOF

python3 /tmp/capture_configs.py

# 7. Compile the final JSON result
cat > /tmp/compile_result.py << 'PYEOF'
import json
import sys

try:
    with open('/tmp/search_result.json', 'r') as f:
        search_res = json.load(f)
        results = search_res.get('results', [])
except:
    results = []

try:
    with open('/tmp/configs.json', 'r') as f:
        configs = json.load(f)
except:
    configs = {}

out = {
    'splunk_running': sys.argv[1] == 'true',
    'test_id': sys.argv[2],
    'results': results,
    'configs': configs
}

with open('/tmp/conditional_routing_result.json', 'w') as f:
    json.dump(out, f)
PYEOF

python3 /tmp/compile_result.py "$SPLUNK_RUNNING" "$TEST_ID"

# 8. Move to final safe location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/conditional_routing_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="