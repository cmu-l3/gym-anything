#!/bin/bash
# Export script for hipaa_escalation_response task

echo "=== Exporting hipaa_escalation_response results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/hipaa_escalation_final.png

TASK_START=$(cat /tmp/hipaa_escalation_start_ts 2>/dev/null || echo "0")
INITIAL_EVENT_COUNT=$(cat /tmp/hipaa_escalation_initial_event_count 2>/dev/null || echo "0")
CURRENT_EVENT_COUNT=$(get_event_count)

# Query ticket state (vtiger_troubletickets uses: title, status, priority, severity)
TICKET_DATA=$(vtiger_db_query "SELECT status, priority, severity FROM vtiger_troubletickets WHERE title='HIPAA audit finding - unencrypted backups' LIMIT 1")
TICKET_STATUS=$(echo "$TICKET_DATA" | awk -F'\t' '{print $1}')
TICKET_PRIORITY=$(echo "$TICKET_DATA" | awk -F'\t' '{print $2}')
TICKET_SEVERITY=$(echo "$TICKET_DATA" | awk -F'\t' '{print $3}')

# Query deal state
DEAL_DATA=$(vtiger_db_query "SELECT sales_stage, probability, closingdate FROM vtiger_potential WHERE potentialname='Pinnacle EHR Security Upgrade' LIMIT 1")
DEAL_STAGE=$(echo "$DEAL_DATA" | awk -F'\t' '{print $1}')
DEAL_PROB=$(echo "$DEAL_DATA" | awk -F'\t' '{print $2}')
DEAL_DATE=$(echo "$DEAL_DATA" | awk -F'\t' '{print $3}')

# Query emergency meeting event
EVENT_DATA=$(vtiger_db_query "SELECT activityid, subject, activitytype, date_start, time_start, time_end, status, location FROM vtiger_activity WHERE subject LIKE '%HIPAA%Pinnacle%' OR subject LIKE '%HIPAA%Emergency%' OR subject LIKE '%Pinnacle%HIPAA%' ORDER BY activityid DESC LIMIT 1")
EVENT_ID=$(echo "$EVENT_DATA" | awk -F'\t' '{print $1}')
EVENT_SUBJECT=$(echo "$EVENT_DATA" | awk -F'\t' '{print $2}')
EVENT_TYPE=$(echo "$EVENT_DATA" | awk -F'\t' '{print $3}')
EVENT_DATE=$(echo "$EVENT_DATA" | awk -F'\t' '{print $4}')
EVENT_START=$(echo "$EVENT_DATA" | awk -F'\t' '{print $5}')
EVENT_END=$(echo "$EVENT_DATA" | awk -F'\t' '{print $6}')
EVENT_STATUS=$(echo "$EVENT_DATA" | awk -F'\t' '{print $7}')
EVENT_LOCATION=$(echo "$EVENT_DATA" | awk -F'\t' '{print $8}')

EVENT_FOUND="False"
[ -n "$EVENT_ID" ] && EVENT_FOUND="True"

python3 << PYEOF
import json

result = {
    "ticket_status": """${TICKET_STATUS:-}""",
    "ticket_priority": """${TICKET_PRIORITY:-}""",
    "ticket_severity": """${TICKET_SEVERITY:-}""",
    "deal_stage": """${DEAL_STAGE:-}""",
    "deal_probability": """${DEAL_PROB:-}""",
    "deal_closedate": """${DEAL_DATE:-}""",
    "event_found": ${EVENT_FOUND},
    "event_id": """${EVENT_ID:-}""",
    "event_subject": """${EVENT_SUBJECT:-}""",
    "event_type": """${EVENT_TYPE:-}""",
    "event_date": """${EVENT_DATE:-}""",
    "event_start": """${EVENT_START:-}""",
    "event_end": """${EVENT_END:-}""",
    "event_status": """${EVENT_STATUS:-}""",
    "event_location": """${EVENT_LOCATION:-}""",
    "initial_event_count": ${INITIAL_EVENT_COUNT},
    "current_event_count": ${CURRENT_EVENT_COUNT},
    "task_start": ${TASK_START}
}

with open('/tmp/hipaa_escalation_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
