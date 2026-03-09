#!/bin/bash
echo "=== Exporting create_asset results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Get Timing Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_COUNT=$(cat /tmp/initial_asset_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM Resources;" 2>/dev/null || echo "0")

# 2. Query Database for the specific asset
# target name: LAPTOP-ENG-0523
ASSET_NAME="LAPTOP-ENG-0523"

# We fetch fields for the asset if it exists.
# Note: SDP schema links Resources -> Product -> ProductType, and Resources -> AssetState
# We retrieve raw values to validate in Python.

# Check existence
EXISTS="false"
RESOURCE_ID=$(sdp_db_exec "SELECT resourceid FROM Resources WHERE LOWER(name) = LOWER('$ASSET_NAME');" 2>/dev/null | head -n 1)

RAW_SERIAL=""
RAW_TAG=""
RAW_DESC=""
RAW_PRODUCT=""
RAW_TYPE=""
RAW_STATE=""
CREATED_TIME="0"

if [ -n "$RESOURCE_ID" ] && [ "$RESOURCE_ID" != "0" ]; then
    EXISTS="true"
    
    # Get Serial, Tag, Description
    # Note: 'serialno' and 'assettag' are columns in Resources or ComponentDefinition depending on version, 
    # but usually Resources handles the main view.
    RAW_SERIAL=$(sdp_db_exec "SELECT serialno FROM Resources WHERE resourceid = $RESOURCE_ID;" 2>/dev/null)
    RAW_TAG=$(sdp_db_exec "SELECT assettag FROM Resources WHERE resourceid = $RESOURCE_ID;" 2>/dev/null)
    RAW_DESC=$(sdp_db_exec "SELECT description FROM Resources WHERE resourceid = $RESOURCE_ID;" 2>/dev/null)
    
    # Get Product Name
    PRODUCT_ID=$(sdp_db_exec "SELECT product_id FROM Resources WHERE resourceid = $RESOURCE_ID;" 2>/dev/null)
    if [ -n "$PRODUCT_ID" ]; then
        RAW_PRODUCT=$(sdp_db_exec "SELECT name FROM Product WHERE id = $PRODUCT_ID;" 2>/dev/null)
        
        # Get Product Type
        TYPE_ID=$(sdp_db_exec "SELECT producttype_id FROM Product WHERE id = $PRODUCT_ID;" 2>/dev/null)
        if [ -n "$TYPE_ID" ]; then
            RAW_TYPE=$(sdp_db_exec "SELECT name FROM ProductType WHERE id = $TYPE_ID;" 2>/dev/null)
        fi
    fi

    # Get Asset State
    STATE_ID=$(sdp_db_exec "SELECT assetstate_id FROM Resources WHERE resourceid = $RESOURCE_ID;" 2>/dev/null)
    if [ -n "$STATE_ID" ]; then
        RAW_STATE=$(sdp_db_exec "SELECT name FROM AssetState WHERE id = $STATE_ID;" 2>/dev/null)
    fi
    
    # Get Creation Time (added_time is usually in milliseconds in SDP)
    ADDED_TIME_MS=$(sdp_db_exec "SELECT added_time FROM Resources WHERE resourceid = $RESOURCE_ID;" 2>/dev/null)
    # Convert to seconds
    CREATED_TIME=$((ADDED_TIME_MS / 1000))
fi

# 3. Construct JSON
# We use a python script to safely build JSON strings to avoid bash quoting issues
python3 -c "
import json
import os

data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'initial_count': int('$INITIAL_COUNT' or 0),
    'current_count': int('$CURRENT_COUNT' or 0),
    'asset_found': '$EXISTS' == 'true',
    'asset_details': {
        'serial': '''$RAW_SERIAL''',
        'tag': '''$RAW_TAG''',
        'product': '''$RAW_PRODUCT''',
        'type': '''$RAW_TYPE''',
        'state': '''$RAW_STATE''',
        'description': '''$RAW_DESC''',
        'created_time': int('$CREATED_TIME' or 0)
    },
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
"

# Set permissions so host can read it via copy_from_env
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json