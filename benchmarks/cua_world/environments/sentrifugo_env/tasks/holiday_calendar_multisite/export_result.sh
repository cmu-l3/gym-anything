#!/bin/bash
echo "=== Exporting holiday_calendar_multisite results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract current holiday groups and dates from MySQL into a TSV file
echo "Extracting database records..."
docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -B -N -e "
SELECT 
    hg.groupname, 
    hd.holidayname, 
    hd.holidaydate 
FROM main_holidaygroups hg 
LEFT JOIN main_holidaydates hd ON hd.groupid = hg.id 
WHERE hg.isactive=1 AND (hd.isactive=1 OR hd.id IS NULL);
" > /tmp/holidays_raw.tsv 2>/dev/null || true

# Extract 'createddate' of the groups to check for anti-gaming
docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -B -N -e "
SELECT groupname, UNIX_TIMESTAMP(createddate) 
FROM main_holidaygroups 
WHERE groupname IN ('Texas Plant Holidays', 'California Plant Holidays', 'Pennsylvania Plant Holidays');
" > /tmp/groups_timestamps.tsv 2>/dev/null || true

# Use Python to convert the TSV dumps to JSON format
cat << 'EOF' > /tmp/parse_results.py
import json
import os

results = {
    "groups": {},
    "group_timestamps": {},
    "task_start_time": int(os.environ.get('TASK_START', 0))
}

# Parse Timestamps
if os.path.exists('/tmp/groups_timestamps.tsv'):
    with open('/tmp/groups_timestamps.tsv', 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 2:
                results["group_timestamps"][parts[0]] = int(parts[1]) if parts[1].isdigit() else 0

# Parse Holiday Data
if os.path.exists('/tmp/holidays_raw.tsv'):
    with open('/tmp/holidays_raw.tsv', 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if not parts or not parts[0]:
                continue
                
            groupname = parts[0]
            if groupname not in results["groups"]:
                results["groups"][groupname] = []
                
            if len(parts) >= 3 and parts[1] and parts[2] and parts[1] != 'NULL':
                results["groups"][groupname].append({
                    "name": parts[1],
                    "date": parts[2].split(' ')[0]  # Take only YYYY-MM-DD
                })

with open('/tmp/task_result.json', 'w') as f:
    json.dump(results, f, indent=2)
EOF

TASK_START=$TASK_START python3 /tmp/parse_results.py

# Clean up
rm -f /tmp/holidays_raw.tsv /tmp/groups_timestamps.tsv /tmp/parse_results.py

# Ensure correct permissions
chmod 666 /tmp/task_result.json

echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="