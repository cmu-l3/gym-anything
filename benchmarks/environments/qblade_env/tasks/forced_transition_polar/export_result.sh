#!/bin/bash
echo "=== Exporting Forced Transition Polar Result ==="

source /workspace/scripts/task_utils.sh

# Files
PROJECT_FILE="/home/ga/Documents/projects/forced_transition_naca0012.wpa"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"
AIRFOIL_FOUND="false"
POLAR_FOUND="false"
REYNOLDS_NUM=0
XTR_TOP=1.0
XTR_BOT=1.0
DATA_POINTS=0

if [ -f "$PROJECT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$PROJECT_FILE")
    FILE_MTIME=$(stat -c%Y "$PROJECT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Parse the .wpa (XML) file using Python to extract XFoil parameters
    # We look for specific tags often used in QBlade project files
    # Note: QBlade XML structure varies, but usually contains <Airfoil> and <Polar> elements
    
    cat > /tmp/parse_qblade_project.py << 'PYEOF'
import sys
import re

try:
    with open(sys.argv[1], 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()

    # Check for NACA 0012
    airfoil_match = re.search(r'NACA\s*0012', content, re.IGNORECASE)
    airfoil_found = "true" if airfoil_match else "false"

    # Extract Polar information
    # Looking for blocks that might define a polar
    # Strategy: Find Reynolds number and Xtr values in close proximity
    
    # Defaults
    reynolds = 0
    xtr_top = 1.0
    xtr_bot = 1.0
    data_count = 0

    # Try to find Re tag
    re_matches = re.findall(r'<Re>([\d\.eE]+)</Re>', content)
    if re_matches:
        # Get the last one or the one closest to 1e6
        for r in re_matches:
            try:
                val = float(r)
                if abs(val - 1000000) < 100000: # Close to target
                    reynolds = val
            except:
                pass
        if reynolds == 0 and len(re_matches) > 0:
             reynolds = float(re_matches[-1])

    # Try to find Xtr tags (QBlade often uses XtrTop, XtrBot or similar)
    xtr_top_match = re.search(r'<XtrTop>([\d\.]+)</XtrTop>', content)
    if xtr_top_match:
        xtr_top = float(xtr_top_match.group(1))
    
    xtr_bot_match = re.search(r'<XtrBot>([\d\.]+)</XtrBot>', content)
    if xtr_bot_match:
        xtr_bot = float(xtr_bot_match.group(1))

    # Also check generic parameter lists if explicit tags fail
    # Sometimes stored as attributes or raw text lists
    
    # Count data points (look for rows of numbers in point data sections)
    # This is rough heuristic for <PolarData> blocks
    # Looking for lines with numbers that look like polar data (alpha, cl, cd...)
    # This regex looks for lines with at least 3 float numbers separated by whitespace
    data_lines = re.findall(r'^\s*[\-\d\.]+\s+[\-\d\.]+\s+[\-\d\.]+', content, re.MULTILINE)
    data_count = len(data_lines)
    
    polar_found = "true" if data_count > 5 else "false"

    print(f"AIRFOIL_FOUND={airfoil_found}")
    print(f"POLAR_FOUND={polar_found}")
    print(f"REYNOLDS_NUM={reynolds}")
    print(f"XTR_TOP={xtr_top}")
    print(f"XTR_BOT={xtr_bot}")
    print(f"DATA_POINTS={data_count}")

except Exception as e:
    print(f"ERROR={str(e)}")
PYEOF

    # Run the parser and source the output
    python3 /tmp/parse_qblade_project.py "$PROJECT_FILE" > /tmp/parsed_values.txt
    source /tmp/parsed_values.txt 2>/dev/null || true
fi

# Check if QBlade is running
APP_RUNNING=$(pgrep -f "QBlade" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "airfoil_found": ${AIRFOIL_FOUND:-false},
    "polar_found": ${POLAR_FOUND:-false},
    "reynolds_num": ${REYNOLDS_NUM:-0},
    "xtr_top": ${XTR_TOP:-1.0},
    "xtr_bot": ${XTR_BOT:-1.0},
    "data_points": ${DATA_POINTS:-0},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
write_result_json "$(cat $TEMP_JSON)"

rm -f "$TEMP_JSON" /tmp/parse_qblade_project.py /tmp/parsed_values.txt

echo "=== Export complete ==="