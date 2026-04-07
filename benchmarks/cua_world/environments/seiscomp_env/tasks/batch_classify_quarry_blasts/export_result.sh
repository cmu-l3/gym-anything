#!/bin/bash
set -e
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Query the Biak Target Events
mysql -u sysop -psysop seiscomp -N -B -e "
SELECT 
    e.publicID, 
    IFNULL(e.type, ''), 
    IFNULL(e.typeCertainty, ''), 
    IFNULL(ed.text, '') 
FROM Event e 
JOIN Origin o ON e.preferredOriginID = o.publicID 
LEFT JOIN EventDescription ed ON e._oid = ed._parent_oid 
WHERE o.latitude BETWEEN -1.7 AND -1.5 
  AND o.longitude BETWEEN 116.0 AND 116.2
" > /tmp/target_events.tsv

# 2. Query the Noto Earthquake (Control)
mysql -u sysop -psysop seiscomp -N -B -e "
SELECT 
    e.publicID, 
    IFNULL(e.type, ''), 
    IFNULL(e.typeCertainty, '')
FROM Event e 
JOIN Origin o ON e.preferredOriginID = o.publicID 
WHERE o.latitude > 30 AND o.longitude > 130
" > /tmp/control_events.tsv

# 3. Convert TSV results to JSON using Python
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 << EOF > "$TEMP_JSON"
import json
import os

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_events": [],
    "control_events": []
}

# Parse target events
if os.path.exists('/tmp/target_events.tsv'):
    with open('/tmp/target_events.tsv', 'r') as f:
        for line in f:
            parts = line.strip('\n').split('\t')
            if len(parts) >= 4:
                result["target_events"].append({
                    "publicID": parts[0],
                    "type": parts[1],
                    "certainty": parts[2],
                    "description": parts[3]
                })

# Parse control events
if os.path.exists('/tmp/control_events.tsv'):
    with open('/tmp/control_events.tsv', 'r') as f:
        for line in f:
            parts = line.strip('\n').split('\t')
            if len(parts) >= 3:
                result["control_events"].append({
                    "publicID": parts[0],
                    "type": parts[1],
                    "certainty": parts[2]
                })

print(json.dumps(result, indent=2))
EOF

# Set permissions and move to final location
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json

echo "=== Export complete ==="