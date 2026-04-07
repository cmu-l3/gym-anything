#!/bin/bash
echo "=== Exporting deck_log_reconstruction results ==="

# Paths
DECK_LOG="/home/ga/Documents/deck_log.txt"
STATS_FILE="/home/ga/Documents/voyage_statistics.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture content of agent output files
LOG_CONTENT=""
STATS_CONTENT=""
LOG_EXISTS="false"
STATS_EXISTS="false"
LOG_MODIFIED="false"
STATS_MODIFIED="false"

if [ -f "$DECK_LOG" ]; then
    LOG_EXISTS="true"
    # Check timestamp
    LOG_MTIME=$(stat -c %Y "$DECK_LOG")
    if [ "$LOG_MTIME" -gt "$TASK_START" ]; then
        LOG_MODIFIED="true"
    fi
    # Read content safely (escape for JSON)
    # We will let Python handle reading later or just dump it to a temp file
    cp "$DECK_LOG" /tmp/agent_deck_log.txt
fi

if [ -f "$STATS_FILE" ]; then
    STATS_EXISTS="true"
    STATS_MTIME=$(stat -c %Y "$STATS_FILE")
    if [ "$STATS_MTIME" -gt "$TASK_START" ]; then
        STATS_MODIFIED="true"
    fi
    cp "$STATS_FILE" /tmp/agent_stats.txt
fi

# 2. EXTRACT GROUND TRUTH DATA
# We run a python script INSIDE the container to parse the raw INI files.
# This ensures the verifier has the exact ground truth of the environment.

cat > /tmp/extract_ground_truth.py << 'PYEOF'
import os
import json
import configparser

# Bridge Command INI files often don't have section headers, or use custom formats.
# We'll use a custom parser for robustness.

def parse_ini(filepath):
    data = {}
    if not os.path.exists(filepath):
        return data
    
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('//') or line.startswith('#') or line.startswith('['):
                    continue
                if '=' in line:
                    key, val = line.split('=', 1)
                    key = key.strip()
                    val = val.strip().strip('"')
                    data[key] = val
    except Exception as e:
        pass
    return data

scenarios_root = "/opt/bridgecommand/Scenarios"
ground_truth = []

if os.path.exists(scenarios_root):
    for d in sorted(os.listdir(scenarios_root)):
        full_path = os.path.join(scenarios_root, d)
        if os.path.isdir(full_path):
            scenario_data = {
                "directory_name": d,
                "environment": parse_ini(os.path.join(full_path, "environment.ini")),
                "ownship": parse_ini(os.path.join(full_path, "ownship.ini")),
                "othership": parse_ini(os.path.join(full_path, "othership.ini"))
            }
            ground_truth.append(scenario_data)

with open('/tmp/ground_truth_scenarios.json', 'w') as f:
    json.dump(ground_truth, f)
PYEOF

python3 /tmp/extract_ground_truth.py

# 3. Create Final Result JSON
# We combine metadata about files and the ground truth data

python3 -c "
import json
import os

result = {
    'deck_log_exists': '$LOG_EXISTS' == 'true',
    'stats_exists': '$STATS_EXISTS' == 'true',
    'deck_log_modified': '$LOG_MODIFIED' == 'true',
    'stats_modified': '$STATS_MODIFIED' == 'true',
    'agent_deck_log_content': '',
    'agent_stats_content': '',
    'scenarios_ground_truth': []
}

# Load agent content
if os.path.exists('/tmp/agent_deck_log.txt'):
    with open('/tmp/agent_deck_log.txt', 'r', errors='ignore') as f:
        result['agent_deck_log_content'] = f.read()

if os.path.exists('/tmp/agent_stats.txt'):
    with open('/tmp/agent_stats.txt', 'r', errors='ignore') as f:
        result['agent_stats_content'] = f.read()

# Load ground truth
if os.path.exists('/tmp/ground_truth_scenarios.json'):
    with open('/tmp/ground_truth_scenarios.json', 'r') as f:
        result['scenarios_ground_truth'] = json.load(f)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# 4. Take screenshot of the Documents folder or terminal (proof of work)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

echo "Result JSON generated at /tmp/task_result.json"