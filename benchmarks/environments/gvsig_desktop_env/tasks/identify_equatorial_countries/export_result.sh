#!/bin/bash
echo "=== Exporting identify_equatorial_countries result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_SHP="/home/ga/gvsig_data/exports/equatorial_countries.shp"
OUTPUT_DBF="/home/ga/gvsig_data/exports/equatorial_countries.dbf"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check file existence and timestamps
SHP_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
SHP_SIZE="0"

if [ -f "$OUTPUT_SHP" ]; then
    SHP_EXISTS="true"
    SHP_SIZE=$(stat -c %s "$OUTPUT_SHP" 2>/dev/null || echo "0")
    SHP_MTIME=$(stat -c %Y "$OUTPUT_SHP" 2>/dev/null || echo "0")
    
    if [ "$SHP_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Extract included countries using python and pyshp
# We extract the ISO_A3 or ADM0_A3 or NAME codes to a list
INCLUDED_COUNTRIES="[]"
FEATURE_COUNT=0

if [ "$SHP_EXISTS" = "true" ] && [ -f "$OUTPUT_DBF" ]; then
    echo "Analyzing shapefile content..."
    
    # Python script to parse DBF and extract country codes
    python3 -c "
import shapefile
import json
import sys

try:
    sf = shapefile.Reader('$OUTPUT_SHP')
    records = sf.records()
    fields = [f[0] for f in sf.fields[1:]] # Skip deletion flag
    
    # Try to find relevant fields
    code_field_idx = -1
    name_field_idx = -1
    
    for i, f in enumerate(fields):
        if f.upper() in ['ISO_A3', 'ADM0_A3', 'SU_A3']:
            code_field_idx = i
        if f.upper() in ['NAME', 'ADMIN', 'NAME_LONG']:
            name_field_idx = i
            
    countries = []
    for r in records:
        data = {}
        if code_field_idx >= 0:
            data['code'] = str(r[code_field_idx]).strip()
        if name_field_idx >= 0:
            data['name'] = str(r[name_field_idx]).strip()
        countries.append(data)
        
    print(json.dumps({'count': len(records), 'countries': countries}))
except Exception as e:
    print(json.dumps({'error': str(e), 'count': 0, 'countries': []}))
" > /tmp/shp_analysis.json 2>/dev/null
    
    if [ -f /tmp/shp_analysis.json ]; then
        INCLUDED_COUNTRIES=$(cat /tmp/shp_analysis.json)
    fi
fi

# Check if app was running
APP_RUNNING=$(pgrep -f "gvSIG" > /dev/null && echo "true" || echo "false")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $SHP_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $SHP_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "analysis": $INCLUDED_COUNTRIES
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="