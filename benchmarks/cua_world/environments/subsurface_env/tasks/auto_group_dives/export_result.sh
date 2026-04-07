#!/bin/bash
set -e
echo "=== Exporting auto_group_dives result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

TASK_FILE="/home/ga/Documents/dives.ssrf"

# Check file states
if [ -f "$TASK_FILE" ]; then
    FILE_EXISTS="true"
    CURRENT_MTIME=$(stat -c%Y "$TASK_FILE" 2>/dev/null || echo "0")
    CURRENT_HASH=$(md5sum "$TASK_FILE" | awk '{print $1}')
else
    FILE_EXISTS="false"
    CURRENT_MTIME="0"
    CURRENT_HASH="none"
fi

INITIAL_MTIME=$(cat /tmp/initial_file_mtime.txt 2>/dev/null || echo "0")
INITIAL_HASH=$(cat /tmp/initial_file_hash.txt 2>/dev/null || echo "none")
INITIAL_TRIPS=$(cat /tmp/initial_trip_count.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if app is running
APP_RUNNING=$(pgrep -f "subsurface" > /dev/null && echo "true" || echo "false")

# Parse XML for trip groupings
python3 << PYEOF > /tmp/task_result.json
import json
import os
import xml.etree.ElementTree as ET

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "app_running": $APP_RUNNING,
    "initial_mtime": $INITIAL_MTIME,
    "current_mtime": $CURRENT_MTIME,
    "initial_hash": "$INITIAL_HASH",
    "current_hash": "$CURRENT_HASH",
    "initial_trips": $INITIAL_TRIPS,
    "xml_stats": {}
}

if "$FILE_EXISTS" == "true":
    try:
        tree = ET.parse("$TASK_FILE")
        root = tree.getroot()
        
        trips = root.findall('.//trip')
        dives_in_trips = sum(len(t.findall('dive')) for t in trips)
        
        dives_container = root.find('dives') if root.find('dives') is not None else root
        ungrouped_dives = len([d for d in dives_container if d.tag == 'dive'])
        
        years = set()
        for t in trips:
            date = t.get('date', '')
            if '2010' in date: years.add('2010')
            if '2011' in date: years.add('2011')
            for d in t.findall('dive'):
                ddate = d.get('date', '')
                if '2010' in ddate: years.add('2010')
                if '2011' in ddate: years.add('2011')
                
        result["xml_stats"] = {
            "success": True,
            "trip_count": len(trips),
            "dives_in_trips": dives_in_trips,
            "ungrouped_dives": ungrouped_dives,
            "has_2010": '2010' in years,
            "has_2011": '2011' in years
        }
    except Exception as e:
        result["xml_stats"] = {
            "success": False,
            "error": str(e)
        }

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="