#!/bin/bash
echo "=== Exporting limit_power_via_pitch_control results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
PROJECT_PATH="/home/ga/Documents/projects/derating_study.wpa"
RESULT_PATH="/home/ga/Documents/projects/target_power_result.txt"
PITCH_PATH="/home/ga/Documents/projects/pitch_setting.txt"

# 1. Check Project File
PROJECT_EXISTS="false"
PROJECT_SIZE=0
if [ -f "$PROJECT_PATH" ]; then
    PROJECT_MTIME=$(stat -c %Y "$PROJECT_PATH" 2>/dev/null || echo "0")
    if [ "$PROJECT_MTIME" -gt "$TASK_START" ]; then
        PROJECT_EXISTS="true"
        PROJECT_SIZE=$(stat -c %s "$PROJECT_PATH" 2>/dev/null || echo "0")
    fi
fi

# 2. Check Pitch Setting File
PITCH_EXISTS="false"
PITCH_VALUE="0"
if [ -f "$PITCH_PATH" ]; then
    PITCH_MTIME=$(stat -c %Y "$PITCH_PATH" 2>/dev/null || echo "0")
    if [ "$PITCH_MTIME" -gt "$TASK_START" ]; then
        PITCH_EXISTS="true"
        # Extract first number found in file
        PITCH_VALUE=$(grep -oE "[0-9]+(\.[0-9]+)?" "$PITCH_PATH" | head -1 || echo "0")
    fi
fi

# 3. Check Simulation Result File and Parse Power
RESULT_EXISTS="false"
POWER_VALUE="0"
WIND_SPEED_CHECK="0"

if [ -f "$RESULT_PATH" ]; then
    RESULT_MTIME=$(stat -c %Y "$RESULT_PATH" 2>/dev/null || echo "0")
    if [ "$RESULT_MTIME" -gt "$TASK_START" ]; then
        RESULT_EXISTS="true"
        
        # Parse the result file using Python to handle various QBlade export formats
        # We look for columns like "Power", "P [W]", etc.
        cat > /tmp/parse_qblade_result.py << 'PY_EOF'
import sys
import re

try:
    with open(sys.argv[1], 'r') as f:
        lines = f.readlines()
    
    header_idx = -1
    power_idx = -1
    
    # Common headers for Power in QBlade exports
    power_keywords = ['Power', 'P [W]', 'P(W)', 'Power [W]']
    
    # Find header line
    for i, line in enumerate(lines):
        # QBlade exports often start with data or have a header line
        tokens = [t.strip() for t in re.split(r'[;,\t\s]+', line) if t.strip()]
        for idx, token in enumerate(tokens):
            if any(k.lower() in token.lower() for k in power_keywords):
                header_idx = i
                power_idx = idx
                break
        if header_idx != -1:
            break
            
    if header_idx != -1 and power_idx != -1:
        # Look for data in subsequent lines
        for i in range(header_idx + 1, len(lines)):
            line = lines[i].strip()
            if not line or not line[0].isdigit() and not line[0] == '-': continue
            
            tokens = [t.strip() for t in re.split(r'[;,\t\s]+', line) if t.strip()]
            if len(tokens) > power_idx:
                try:
                    p = float(tokens[power_idx])
                    print(f"{p}")
                    sys.exit(0)
                except ValueError:
                    continue
    
    # Fallback: if no header found, look for typical value near 50000
    for line in lines:
        tokens = [t.strip() for t in re.split(r'[;,\t\s]+', line) if t.strip()]
        for token in tokens:
            try:
                val = float(token)
                # If it's in a plausible range for this task (10kW to 1MW), take it
                if 40000 <= val <= 60000:
                    print(f"{val}")
                    sys.exit(0)
            except ValueError:
                continue

    print("0")
except Exception as e:
    print("0")
PY_EOF
        
        POWER_VALUE=$(python3 /tmp/parse_qblade_result.py "$RESULT_PATH")
    fi
fi

# Check if QBlade is still running
APP_RUNNING=$(pgrep -f "QBlade" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_size_bytes": $PROJECT_SIZE,
    "pitch_file_exists": $PITCH_EXISTS,
    "pitch_value": $PITCH_VALUE,
    "result_file_exists": $RESULT_EXISTS,
    "measured_power_watts": $POWER_VALUE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="