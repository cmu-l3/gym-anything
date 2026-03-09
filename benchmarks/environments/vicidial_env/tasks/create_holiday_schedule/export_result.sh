#!/bin/bash
set -e

echo "=== Exporting create_holiday_schedule result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Export Database Data
# We query the holidays table for all entries in 2025.
# We select specific columns to verify against the task requirements.

echo "Querying Vicidial database for holidays..."
QUERY="SELECT holiday_id, holiday_name, holiday_date, holiday_status, ct_default_start, ct_default_stop FROM vicidial_call_time_holidays WHERE holiday_date BETWEEN '2025-01-01' AND '2025-12-31' ORDER BY holiday_date ASC;"

# Create a temporary JSON file from the SQL query
# We use python to run the docker exec and format as JSON to avoid bash parsing hell
python3 -c "
import subprocess
import json
import time

try:
    cmd = ['docker', 'exec', 'vicidial', 'mysql', '-ucron', '-p1234', '-D', 'asterisk', '-e', '$QUERY', '-B']
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    rows = []
    if result.returncode == 0:
        lines = result.stdout.strip().split('\n')
        if len(lines) > 1:
            headers = lines[0].split('\t')
            for line in lines[1:]:
                values = line.split('\t')
                row_dict = dict(zip(headers, values))
                rows.append(row_dict)
    
    output = {
        'holidays': rows,
        'timestamp': time.time(),
        'query_success': result.returncode == 0
    }
    
    with open('/tmp/holiday_data.json', 'w') as f:
        json.dump(output, f, indent=2)
        
except Exception as e:
    print(f'Error exporting data: {e}')
    with open('/tmp/holiday_data.json', 'w') as f:
        json.dump({'error': str(e), 'holidays': []}, f)
"

# 3. Secure the result file for copying
chmod 644 /tmp/holiday_data.json

# 4. Create main result wrapper
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "holiday_data_path": "/tmp/holiday_data.json",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Data saved to /tmp/task_result.json and /tmp/holiday_data.json"
cat /tmp/holiday_data.json