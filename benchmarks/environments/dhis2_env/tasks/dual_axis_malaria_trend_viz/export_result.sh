#!/bin/bash
# Export script for Dual Axis Malaria Trend Visualization task

echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

# Fallback API
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
fi

# 1. Take Final Screenshot
take_screenshot /tmp/task_end.png

# 2. Check File Artifact
FILE_PATH="/home/ga/Desktop/malaria_chart.png"
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_AFTER_START="false"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$FILE_PATH")
    FILE_MTIME=$(stat -c%Y "$FILE_PATH")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_AFTER_START="true"
    fi
fi

# 3. Query DHIS2 for the Visualization
echo "Querying DHIS2 for visualization..."
# Fetch detailed fields to verify dual axis configuration
# We look for 'axes', 'series', 'optionalAxes' depending on DHIS2 version
VIZ_JSON=$(dhis2_api "visualizations?filter=displayName:ilike:Bo+Malaria+Testing+vs+Positivity+2024&fields=id,displayName,created,type,columns,rows,filters,axes,series,dataDimensionItems[dataDimensionItemType,indicator[id,displayName],dataElement[id,displayName]]&paging=false" 2>/dev/null)

# 4. Construct Result JSON
cat > /tmp/task_result.json <<EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_after_start": $FILE_CREATED_AFTER_START,
    "viz_api_response": $VIZ_JSON,
    "task_start_timestamp": $TASK_START,
    "export_timestamp": $(date +%s)
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="