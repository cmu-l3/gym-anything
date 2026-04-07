#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/bat_curtailment_analysis.json"

FILE_EXISTS="false"
FILE_MODIFIED="false"
PYTHON_RAN="false"

if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c%Y "$EXPECTED_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Extract parameters from the agent's JSON
AGENT_BASELINE="0"
AGENT_CURTAILED="0"
AGENT_PENALTY="0"
AGENT_HOURS="0"

if [ "$FILE_EXISTS" = "true" ] && command -v jq &> /dev/null; then
    if jq empty "$EXPECTED_FILE" 2>/dev/null; then
        AGENT_BASELINE=$(jq -r '.baseline_energy_kwh // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        AGENT_CURTAILED=$(jq -r '.curtailed_energy_kwh // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        AGENT_PENALTY=$(jq -r '.energy_penalty_kwh // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        AGENT_HOURS=$(jq -r '.curtailed_hours_count // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
    fi
fi

# Generate ground truth via PySAM inside the container
echo "Generating ground truth data..."
cat > /tmp/generate_gt.py << 'EOF'
import PySAM.Windpower as wp
import os
import glob
import json
import datetime

def generate_ground_truth():
    sam_dir = ""
    if os.path.exists("/opt/SAM/sam_dir.txt"):
        with open("/opt/SAM/sam_dir.txt") as f:
            sam_dir = f.read().strip()
    
    if not sam_dir:
        sam_dir = "/opt/SAM/2024.12.12"
        
    wfs = glob.glob(f"{sam_dir}/**/wyoming_wind_resource_dataset.csv", recursive=True)
    if not wfs:
        wfs = glob.glob(f"{sam_dir}/**/wind_resource/*.csv", recursive=True)
        if not wfs:
            wfs = glob.glob("/opt/SAM/**/wind_resource/*.csv", recursive=True)
            
    if not wfs:
        return {"error": "No wind resource file found"}
        
    wf = wfs[0]
    
    model = wp.default('Wind Power Single Owner')
    model.Resource.wind_resource_filename = wf
    model.execute()
    
    gen = model.Outputs.gen
    wind_speed = model.Outputs.wind_speed
    
    baseline_energy = sum(gen)
    curtailed_energy = 0
    curtailed_hours = 0
    
    start_time = datetime.datetime(2022, 1, 1, 0, 0)
    
    for i in range(8760):
        current_time = start_time + datetime.timedelta(hours=i)
        month = current_time.month
        hour = current_time.hour
        ws = wind_speed[i]
        
        is_fall = month in [8, 9, 10]
        is_night = hour >= 20 or hour <= 5
        is_low_wind = ws < 6.0
        
        if is_fall and is_night and is_low_wind:
            curtailed_hours += 1
        else:
            curtailed_energy += gen[i]
            
    energy_penalty = baseline_energy - curtailed_energy
    
    result = {
        "baseline_energy_kwh": float(baseline_energy),
        "curtailed_energy_kwh": float(curtailed_energy),
        "energy_penalty_kwh": float(energy_penalty),
        "curtailed_hours_count": int(curtailed_hours),
        "weather_file_used": wf
    }
    
    with open("/tmp/ground_truth.json", "w") as f:
        json.dump(result, f)

if __name__ == "__main__":
    try:
        generate_ground_truth()
    except Exception as e:
        with open("/tmp/ground_truth.json", "w") as f:
            json.dump({"error": str(e)}, f)
EOF

python3 /tmp/generate_gt.py

# Create final task result JSON safely using jq
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson python_ran "$PYTHON_RAN" \
    --arg baseline "$AGENT_BASELINE" \
    --arg curtailed "$AGENT_CURTAILED" \
    --arg penalty "$AGENT_PENALTY" \
    --arg hours "$AGENT_HOURS" \
    '{
        file_exists: $file_exists,
        file_modified: $file_modified,
        python_ran: $python_ran,
        agent_baseline: $baseline,
        agent_curtailed: $curtailed,
        agent_penalty: $penalty,
        agent_hours: $hours
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/ground_truth.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="