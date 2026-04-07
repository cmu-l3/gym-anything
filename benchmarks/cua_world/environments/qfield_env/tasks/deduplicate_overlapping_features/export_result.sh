#!/bin/bash
echo "=== Exporting Deduplication Results ==="

# Paths
ANDROID_GPKG="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"
LOCAL_GPKG="/tmp/world_survey_final.gpkg"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture final screenshot
adb shell screencap -p /sdcard/task_final.png
adb pull /sdcard/task_final.png /tmp/task_final.png

# 2. Pull the GeoPackage to analyze
echo "Pulling GeoPackage for analysis..."
if adb pull "$ANDROID_GPKG" "$LOCAL_GPKG"; then
    GPKG_EXISTS="true"
    
    # Check file modification time on device
    # ls -l format on Android: "-rw-rw---- 1 u0_a136 media_rw 741376 2023-10-27 10:00 filename"
    # We'll use stat if available, or just rely on content changes
    FILE_MODIFIED="true" # We will verify content change which implies modification
else
    GPKG_EXISTS="false"
    FILE_MODIFIED="false"
fi

# 3. Analyze Database Content with Python
# We need to output JSON for the verifier
python3 -c "
import sqlite3
import json
import os
import sys

result = {
    'rome_count': 0,
    'has_legacy_duplicate': False,
    'has_valid_rome': False,
    'total_capitals': 0,
    'error': None
}

try:
    if '$GPKG_EXISTS' == 'true':
        conn = sqlite3.connect('$LOCAL_GPKG')
        cursor = conn.cursor()
        
        # Find table
        cursor.execute(\"SELECT table_name FROM gpkg_contents WHERE identifier LIKE '%capital%'\")
        res = cursor.fetchone()
        if res:
            table_name = res[0]
            
            # Count Rome features
            cursor.execute(f\"SELECT count(*) FROM {table_name} WHERE name='Rome'\")
            result['rome_count'] = cursor.fetchone()[0]
            
            # Check for legacy duplicate
            cursor.execute(f\"SELECT count(*) FROM {table_name} WHERE name='Rome' AND description='LEGACY_DUPLICATE'\")
            result['has_legacy_duplicate'] = (cursor.fetchone()[0] > 0)
            
            # Check for valid Rome (Rome exists AND is NOT Legacy Duplicate)
            cursor.execute(f\"SELECT count(*) FROM {table_name} WHERE name='Rome' AND (description IS NULL OR description != 'LEGACY_DUPLICATE')\")
            result['has_valid_rome'] = (cursor.fetchone()[0] > 0)
            
            # Total count
            cursor.execute(f\"SELECT count(*) FROM {table_name}\")
            result['total_capitals'] = cursor.fetchone()[0]
            
        conn.close()
    else:
        result['error'] = 'GeoPackage not found'

except Exception as e:
    result['error'] = str(e)

# Write result to file
with open('/tmp/db_analysis.json', 'w') as f:
    json.dump(result, f)
"

# 4. Create Final JSON for Verifier
# Combine DB analysis with system stats
cat > /tmp/temp_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png",
    "db_analysis": $(cat /tmp/db_analysis.json)
}
EOF

# Move to standard location
mv /tmp/temp_result.json /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json