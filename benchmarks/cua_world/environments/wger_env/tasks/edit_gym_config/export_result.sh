#!/bin/bash
echo "=== Exporting edit_gym_config result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Extract all Gym records from the database directly.
# This approach avoids guessing exact field names (e.g., zip vs zip_code)
# by dumping the entire __dict__ for all gyms to JSON.
echo "Extracting gym records from database..."
docker exec wger-web python3 manage.py shell -c "
import json
try:
    from wger.gym.models import Gym
    gyms = Gym.objects.all()
    res = []
    for g in gyms:
        # Extract fields, converting to string to handle UUIDs/Dates safely
        d = {k: str(v) for k, v in g.__dict__.items() if not k.startswith('_')}
        res.append(d)
    print('JSON_START' + json.dumps(res) + 'JSON_END')
except Exception as e:
    print('JSON_START[]JSON_END')
" > /tmp/gym_export_raw.txt

# Parse out just the JSON portion between the markers
sed -n 's/.*JSON_START\(.*\)JSON_END.*/\1/p' /tmp/gym_export_raw.txt > /tmp/gyms.json

# If parsing failed or output is empty, fallback to an empty array
if [ ! -s /tmp/gyms.json ]; then
    echo "[]" > /tmp/gyms.json
fi

# Create a consolidated JSON payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "gyms": $(cat /tmp/gyms.json),
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false")
}
EOF

# Use sudo where needed to prevent permission errors on the host mapping
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved."
echo "=== Export complete ==="