#!/bin/bash
# Export script for MTM Heartbeat task

echo "=== Exporting MTM Heartbeat Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check if a container exists for Site 1
echo "Checking for container..."
CONTAINER_DATA=$(matomo_query "SELECT idcontainer, name, published_version_id FROM matomo_tagmanager_container WHERE idsite=1 ORDER BY idcontainer DESC LIMIT 1" 2>/dev/null)

CONTAINER_FOUND="false"
CONTAINER_ID=""
CONTAINER_NAME=""
PUBLISHED_VERSION_ID=""

if [ -n "$CONTAINER_DATA" ]; then
    CONTAINER_FOUND="true"
    CONTAINER_ID=$(echo "$CONTAINER_DATA" | cut -f1)
    CONTAINER_NAME=$(echo "$CONTAINER_DATA" | cut -f2)
    PUBLISHED_VERSION_ID=$(echo "$CONTAINER_DATA" | cut -f3)
    echo "Container found: ID=$CONTAINER_ID, Name=$CONTAINER_NAME, PublishedVersion=$PUBLISHED_VERSION_ID"
else
    echo "No container found for Site 1."
fi

# 2. If published version exists, get its content (JSON blob)
# We need to be careful exporting large JSON blobs via bash/mysql CLI
# usage of -B (batch) and sed to handle potential newlines/quotes
VERSION_CONTENT=""
VERSION_NAME=""

if [ "$CONTAINER_FOUND" = "true" ] && [ -n "$PUBLISHED_VERSION_ID" ] && [ "$PUBLISHED_VERSION_ID" != "NULL" ]; then
    echo "Fetching published version content..."
    
    # Get name
    VERSION_NAME=$(matomo_query "SELECT name FROM matomo_tagmanager_container_version WHERE idcontainerversion=$PUBLISHED_VERSION_ID" 2>/dev/null)
    
    # Get content - dump to a temp file to avoid shell variable limits/escaping hell
    docker exec matomo-db mysql -u matomo -pmatomo123 matomo -N -B -e "SELECT content FROM matomo_tagmanager_container_version WHERE idcontainerversion=$PUBLISHED_VERSION_ID" > /tmp/version_content_raw.json 2>/dev/null
    
    if [ -s /tmp/version_content_raw.json ]; then
        # The content from DB might contain escaped chars that need handling
        # For now, we will read it in python in the next step to constructing the JSON
        echo "Version content retrieved."
    else
        echo "Failed to retrieve version content or empty."
    fi
else
    echo "No published version ID found."
fi

# 3. Create Result JSON
# We use a python one-liner to safely construct the JSON with the raw content file
# This avoids bash string escaping issues with the complex JSON blob from the DB

python3 -c "
import json
import os
import time

try:
    task_start = int('$TASK_START')
    task_end = int('$TASK_END')
    container_found = '$CONTAINER_FOUND' == 'true'
    container_id = '$CONTAINER_ID'
    container_name = '$CONTAINER_NAME'
    published_id = '$PUBLISHED_VERSION_ID'
    version_name = '$VERSION_NAME'
    
    content = {}
    if os.path.exists('/tmp/version_content_raw.json'):
        with open('/tmp/version_content_raw.json', 'r') as f:
            raw = f.read().strip()
            if raw:
                try:
                    content = json.loads(raw)
                except:
                    content = {'error': 'failed_to_parse_db_json', 'raw_snippet': raw[:100]}

    result = {
        'task_start': task_start,
        'task_end': task_end,
        'container_found': container_found,
        'container_id': container_id,
        'container_name': container_name,
        'published_version_id': published_id,
        'published_version_name': version_name,
        'published_content': content
    }
    
    with open('/tmp/mtm_heartbeat_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
except Exception as e:
    print(f'Error generating JSON: {e}')
"

# Set permissions
chmod 666 /tmp/mtm_heartbeat_result.json 2>/dev/null || true

echo "Result JSON saved to /tmp/mtm_heartbeat_result.json"
echo "=== Export Complete ==="