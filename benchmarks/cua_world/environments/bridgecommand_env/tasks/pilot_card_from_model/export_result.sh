#!/bin/bash
echo "=== Exporting pilot_card_from_model result ==="

# Define paths
PILOT_CARD="/home/ga/Documents/pilot_card.txt"
SCENARIO_DIR="/opt/bridgecommand/Scenarios/p) Solent Pilotage Approach"
BC_CONFIG="/home/ga/.config/Bridge Command/bc5.ini"
EXPORT_DIR="/tmp/export_data"
mkdir -p "$EXPORT_DIR"

# 1. Export Pilot Card
if [ -f "$PILOT_CARD" ]; then
    cp "$PILOT_CARD" "$EXPORT_DIR/pilot_card.txt"
    echo "Exported pilot card"
else
    echo "Pilot card not found"
fi

# 2. Export Scenario Files
if [ -d "$SCENARIO_DIR" ]; then
    cp "$SCENARIO_DIR/environment.ini" "$EXPORT_DIR/scenario_environment.ini" 2>/dev/null || true
    cp "$SCENARIO_DIR/ownship.ini" "$EXPORT_DIR/scenario_ownship.ini" 2>/dev/null || true
    cp "$SCENARIO_DIR/othership.ini" "$EXPORT_DIR/scenario_othership.ini" 2>/dev/null || true
    echo "Exported scenario files"
else
    echo "Scenario directory not found"
fi

# 3. Export Config (to check hide_instruments)
if [ -f "$BC_CONFIG" ]; then
    cp "$BC_CONFIG" "$EXPORT_DIR/bc5.ini"
else
    # Try alternate location
    cp "/opt/bridgecommand/bc5.ini" "$EXPORT_DIR/bc5.ini" 2>/dev/null || true
fi

# 4. Export Model Data (Ground Truth)
# We scan ALL models and create a summary JSON. 
# This allows the verifier to fuzzy-match the agent's work against any available model.
echo "Scanning available models for ground truth..."
python3 -c "
import os
import configparser
import json

models_dir = '/opt/bridgecommand/Models'
models_data = {}

if os.path.exists(models_dir):
    for model_name in os.listdir(models_dir):
        model_path = os.path.join(models_dir, model_name)
        ini_path = os.path.join(model_path, 'ownship.ini')
        if os.path.isdir(model_path) and os.path.exists(ini_path):
            try:
                # Manual parsing because INI files might lack headers or have loose syntax
                props = {}
                with open(ini_path, 'r', errors='ignore') as f:
                    for line in f:
                        if '=' in line:
                            key, val = line.split('=', 1)
                            props[key.strip().lower()] = val.strip()
                models_data[model_name] = props
            except Exception as e:
                print(f'Error parsing {model_name}: {e}')

with open('/tmp/export_data/models_ground_truth.json', 'w') as f:
    json.dump(models_data, f, indent=2)
"

# 5. Metadata for verification
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PILOT_CARD_MTIME=0
if [ -f "$PILOT_CARD" ]; then
    PILOT_CARD_MTIME=$(stat -c %Y "$PILOT_CARD")
fi

cat > "$EXPORT_DIR/metadata.json" << EOF
{
    "task_start_time": $TASK_START,
    "pilot_card_mtime": $PILOT_CARD_MTIME,
    "pilot_card_exists": $([ -f "$PILOT_CARD" ] && echo "true" || echo "false"),
    "scenario_exists": $([ -d "$SCENARIO_DIR" ] && echo "true" || echo "false")
}
EOF

# 6. Capture final screenshot
su - ga -c "DISPLAY=:1 scrot /tmp/task_final.png" 2>/dev/null || true
cp /tmp/task_final.png "$EXPORT_DIR/screenshot.png" 2>/dev/null || true

# 7. Package into single JSON for verifier
# We read files into the JSON structure to avoid multi-file copying issues
python3 -c "
import json
import os

base = '/tmp/export_data'
result = {}

# Load metadata
try:
    with open(f'{base}/metadata.json') as f:
        result.update(json.load(f))
except: pass

# Load pilot card content
try:
    with open(f'{base}/pilot_card.txt') as f:
        result['pilot_card_content'] = f.read()
except:
    result['pilot_card_content'] = None

# Load scenario files
result['scenario'] = {}
for ini in ['environment', 'ownship', 'othership']:
    try:
        with open(f'{base}/scenario_{ini}.ini') as f:
            result['scenario'][ini] = f.read()
    except:
        result['scenario'][ini] = None

# Load bc5 config
try:
    with open(f'{base}/bc5.ini') as f:
        result['bc5_content'] = f.read()
except:
    result['bc5_content'] = None

# Load models ground truth
try:
    with open(f'{base}/models_ground_truth.json') as f:
        result['models_db'] = json.load(f)
except:
    result['models_db'] = {}

# Save final result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# 8. Clean up
rm -rf "$EXPORT_DIR"
echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json | head -n 20