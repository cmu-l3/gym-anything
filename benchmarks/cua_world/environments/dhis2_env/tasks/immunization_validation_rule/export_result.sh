#!/bin/bash
# Export script for Immunization Validation Rule task

echo "=== Exporting Immunization Validation Rule Result ==="

source /workspace/scripts/task_utils.sh

if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")
TASK_START_EPOCH=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Check for new Validation Rules
echo "Querying new validation rules..."
RULES_RESULT=$(dhis2_api "validationRules?fields=id,displayName,created,operator,leftSide[expression,description],rightSide[expression,description]&paging=false&order=created:desc" 2>/dev/null | \
python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    try:
        # Normalize DHIS2 date string if needed
        ts_clean = task_start_iso.replace('Z', '+00:00')
        task_start = datetime.fromisoformat(ts_clean)
    except:
        task_start = datetime(2020, 1, 1)

    new_rules = []
    for r in data.get('validationRules', []):
        created_str = r.get('created', '2000-01-01T00:00:00')
        try:
            # Handle variable timezone formats from DHIS2
            created_str = created_str.replace('Z', '+00:00')
            created = datetime.fromisoformat(created_str)
            # Simple check if created >= task_start (ignoring slight clock skew if any)
            if created.timestamp() >= task_start.timestamp() - 10:
                new_rules.append(r)
        except:
            pass
            
    # Filter for relevant rules
    penta_rules = [r for r in new_rules if 'penta' in r.get('displayName', '').lower()]

    print(json.dumps({
        'new_rules_count': len(new_rules),
        'penta_rules': penta_rules
    }))
except Exception as e:
    print(json.dumps({'new_rules_count': 0, 'penta_rules': [], 'error': str(e)}))
" 2>/dev/null)

# 2. Check for new Validation Rule Groups
echo "Querying new validation rule groups..."
GROUPS_RESULT=$(dhis2_api "validationRuleGroups?fields=id,displayName,created,validationRules[id]&paging=false&order=created:desc" 2>/dev/null | \
python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    try:
        ts_clean = task_start_iso.replace('Z', '+00:00')
        task_start = datetime.fromisoformat(ts_clean)
    except:
        task_start = datetime(2020, 1, 1)

    new_groups = []
    for g in data.get('validationRuleGroups', []):
        created_str = g.get('created', '')
        try:
            created_str = created_str.replace('Z', '+00:00')
            created = datetime.fromisoformat(created_str)
            if created.timestamp() >= task_start.timestamp() - 10:
                new_groups.append(g)
        except:
            pass
            
    imm_groups = [g for g in new_groups if 'immunization' in g.get('displayName', '').lower() or 'quality' in g.get('displayName', '').lower()]

    print(json.dumps({
        'new_groups_count': len(new_groups),
        'relevant_groups': imm_groups
    }))
except Exception as e:
    print(json.dumps({'new_groups_count': 0, 'relevant_groups': [], 'error': str(e)}))
" 2>/dev/null)

# 3. Check Results File
FILE_PATH="/home/ga/Desktop/validation_results.txt"
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CONTENT=""
FILE_CREATED_AFTER_START="false"

if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$FILE_PATH")
    FILE_MTIME=$(stat -c%Y "$FILE_PATH")
    
    if [ "$FILE_MTIME" -ge "$TASK_START_EPOCH" ]; then
        FILE_CREATED_AFTER_START="true"
    fi
    
    # Read first 500 chars for context check
    FILE_CONTENT=$(head -c 500 "$FILE_PATH" | tr '\n' ' ' | sed 's/"/\\"/g')
fi

# Combine all into JSON
cat > /tmp/immunization_validation_rule_result.json << ENDJSON
{
    "task_start_iso": "$TASK_START_ISO",
    "rules_data": $RULES_RESULT,
    "groups_data": $GROUPS_RESULT,
    "file_info": {
        "exists": $FILE_EXISTS,
        "size": $FILE_SIZE,
        "created_after_start": $FILE_CREATED_AFTER_START,
        "content_snippet": "$FILE_CONTENT"
    },
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

chmod 666 /tmp/immunization_validation_rule_result.json 2>/dev/null || true

echo "Result JSON saved."
echo "=== Export Complete ==="