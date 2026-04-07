#!/bin/bash
echo "=== Exporting Scenario Archive Catalog Result ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Define Paths
CATALOG_FILE="/home/ga/Documents/scenario_catalog.json"
CHECKSUM_FILE="/home/ga/Documents/scenario_checksums.sha256"
REPORT_FILE="/home/ga/Documents/preservation_report.txt"
SCENARIOS_ROOT="/opt/bridgecommand/Scenarios"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Read Agent Outputs
AGENT_CATALOG_CONTENT="[]"
AGENT_CHECKSUM_CONTENT=""
AGENT_REPORT_CONTENT=""
CATALOG_EXISTS="false"
CHECKSUM_EXISTS="false"
REPORT_EXISTS="false"

if [ -f "$CATALOG_FILE" ]; then
    # Check timestamp
    F_TIME=$(stat -c %Y "$CATALOG_FILE")
    if [ "$F_TIME" -ge "$TASK_START" ]; then
        CATALOG_EXISTS="true"
        # Read content, safeguarding against massive files
        AGENT_CATALOG_CONTENT=$(cat "$CATALOG_FILE" | head -c 100000) 
    fi
fi

if [ -f "$CHECKSUM_FILE" ]; then
    F_TIME=$(stat -c %Y "$CHECKSUM_FILE")
    if [ "$F_TIME" -ge "$TASK_START" ]; then
        CHECKSUM_EXISTS="true"
        AGENT_CHECKSUM_CONTENT=$(head -n 20 "$CHECKSUM_FILE") # Get first 20 lines for verification
        TOTAL_CHECKSUMS=$(wc -l < "$CHECKSUM_FILE")
    else
        TOTAL_CHECKSUMS=0
    fi
fi

if [ -f "$REPORT_FILE" ]; then
    F_TIME=$(stat -c %Y "$REPORT_FILE")
    if [ "$F_TIME" -ge "$TASK_START" ]; then
        REPORT_EXISTS="true"
        AGENT_REPORT_CONTENT=$(cat "$REPORT_FILE" | head -c 5000)
    fi
fi

# 4. Generate Ground Truth (using Python to parse actual scenarios)
# We do this here so the verifier (on host) has the source of truth from the container
python3 -c "
import os
import json
import configparser

scenarios_root = '$SCENARIOS_ROOT'
ground_truth = []

def parse_ini_dummy(filepath):
    # Bridge Command INI files often lack section headers or have duplicates
    # We use a simple line parser
    data = {}
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()
                if '=' in line and not line.startswith(';'):
                    key, val = line.split('=', 1)
                    key = key.strip()
                    val = val.strip().strip('\"')
                    data[key] = val
    except:
        pass
    return data

def count_otherships(filepath):
    if not os.path.exists(filepath):
        return 0
    data = parse_ini_dummy(filepath)
    # Check for 'Number' key
    if 'Number' in data:
        try:
            return int(data['Number'])
        except:
            pass
    
    # Fallback: count distinct indices in Type(N)
    indices = set()
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                if line.strip().startswith('Type('):
                    # Extract N from Type(N)
                    try:
                        idx = line.split('(')[1].split(')')[0]
                        indices.add(idx)
                    except:
                        pass
    except:
        pass
    return len(indices)

if os.path.exists(scenarios_root):
    for entry in sorted(os.listdir(scenarios_root)):
        full_path = os.path.join(scenarios_root, entry)
        if os.path.isdir(full_path):
            env_path = os.path.join(full_path, 'environment.ini')
            own_path = os.path.join(full_path, 'ownship.ini')
            other_path = os.path.join(full_path, 'othership.ini')
            
            env_data = parse_ini_dummy(env_path)
            own_data = parse_ini_dummy(own_path)
            vessel_count = count_otherships(other_path)
            
            files = os.listdir(full_path)
            
            is_complete = os.path.exists(env_path) and os.path.exists(own_path) and os.path.exists(other_path)
            
            ground_truth.append({
                'scenario_name': entry,
                'directory_path': full_path,
                'world_model': env_data.get('Setting', None),
                'own_ship_name': own_data.get('ShipName', None),
                'traffic_vessel_count': vessel_count,
                'is_complete': is_complete
            })

with open('/tmp/ground_truth.json', 'w') as f:
    json.dump(ground_truth, f)
"

GROUND_TRUTH_CONTENT=$(cat /tmp/ground_truth.json 2>/dev/null || echo "[]")

# 5. Package into Final JSON
# We use a temporary Python script to ensure valid JSON escaping
python3 -c "
import json
import sys

output = {
    'catalog_exists': $CATALOG_EXISTS,
    'checksum_exists': $CHECKSUM_EXISTS,
    'report_exists': $REPORT_EXISTS,
    'total_checksums_lines': ${TOTAL_CHECKSUMS:-0},
    'agent_catalog_raw': '''$AGENT_CATALOG_CONTENT''',
    'agent_checksum_sample': '''$AGENT_CHECKSUM_CONTENT''',
    'agent_report_content': '''$AGENT_REPORT_CONTENT''',
    'ground_truth': $GROUND_TRUTH_CONTENT
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(output, f)
"

# 6. Copy to location expected by framework (if needed) or just cat it for debugging
cat /tmp/task_result.json
echo "=== Export Complete ==="