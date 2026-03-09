#!/bin/bash
# Export script for lost_deal_reactivation_and_contact_fix task

echo "=== Exporting lost_deal_reactivation_and_contact_fix results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/ironshield_final.png

TASK_START=$(cat /tmp/ironshield_start_ts 2>/dev/null || echo "0")

# --- Query IronShield Deal ---
DEAL_DATA=$(vtiger_db_query "SELECT potentialid, potentialname, amount, sales_stage, probability, closingdate FROM vtiger_potential WHERE potentialname='IronShield Network Hardening' LIMIT 1")
DEAL_ID=$(echo "$DEAL_DATA" | awk -F'\t' '{print $1}')
DEAL_AMOUNT=$(echo "$DEAL_DATA" | awk -F'\t' '{print $3}')
DEAL_STAGE=$(echo "$DEAL_DATA" | awk -F'\t' '{print $4}')
DEAL_PROB=$(echo "$DEAL_DATA" | awk -F'\t' '{print $5}')
DEAL_DATE=$(echo "$DEAL_DATA" | awk -F'\t' '{print $6}')

DEAL_FOUND="False"
[ -n "$DEAL_ID" ] && DEAL_FOUND="True"

# --- Query Victoria Blackwell ---
VB_DATA=$(vtiger_db_query "SELECT contactid, firstname, lastname, email, phone, title FROM vtiger_contactdetails WHERE firstname='Victoria' AND lastname='Blackwell' LIMIT 1")
VB_ID=$(echo "$VB_DATA" | awk -F'\t' '{print $1}')
VB_EMAIL=$(echo "$VB_DATA" | awk -F'\t' '{print $4}')
VB_TITLE=$(echo "$VB_DATA" | awk -F'\t' '{print $6}')

VB_FOUND="False"
[ -n "$VB_ID" ] && VB_FOUND="True"

# --- Query Thomas Park ---
TP_DATA=$(vtiger_db_query "SELECT contactid, firstname, lastname, email, phone, title FROM vtiger_contactdetails WHERE firstname='Thomas' AND lastname='Park' LIMIT 1")
TP_ID=$(echo "$TP_DATA" | awk -F'\t' '{print $1}')
TP_PHONE=$(echo "$TP_DATA" | awk -F'\t' '{print $5}')
TP_TITLE=$(echo "$TP_DATA" | awk -F'\t' '{print $6}')

TP_FOUND="False"
[ -n "$TP_ID" ] && TP_FOUND="True"

# --- Query Reactivation Call Event ---
CALL_DATA=$(vtiger_db_query "SELECT activityid, subject, activitytype, date_start, time_start, time_end, status FROM vtiger_activity WHERE (subject LIKE '%IronShield%Reactivation%' OR subject LIKE '%Blackstone%IronShield%') AND activitytype='Call' ORDER BY activityid DESC LIMIT 1")
CALL_ID=$(echo "$CALL_DATA" | awk -F'\t' '{print $1}')
CALL_SUBJECT=$(echo "$CALL_DATA" | awk -F'\t' '{print $2}')
CALL_TYPE=$(echo "$CALL_DATA" | awk -F'\t' '{print $3}')
CALL_DATE=$(echo "$CALL_DATA" | awk -F'\t' '{print $4}')
CALL_START=$(echo "$CALL_DATA" | awk -F'\t' '{print $5}')
CALL_END=$(echo "$CALL_DATA" | awk -F'\t' '{print $6}')
CALL_STATUS=$(echo "$CALL_DATA" | awk -F'\t' '{print $7}')

CALL_FOUND="False"
[ -n "$CALL_ID" ] && CALL_FOUND="True"

python3 << PYEOF
import json

result = {
    "deal_found": ${DEAL_FOUND},
    "deal_id": """${DEAL_ID:-}""",
    "deal_amount": """${DEAL_AMOUNT:-}""",
    "deal_stage": """${DEAL_STAGE:-}""",
    "deal_probability": """${DEAL_PROB:-}""",
    "deal_closedate": """${DEAL_DATE:-}""",
    "contact_vb_found": ${VB_FOUND},
    "contact_vb_id": """${VB_ID:-}""",
    "contact_vb_email": """${VB_EMAIL:-}""",
    "contact_vb_title": """${VB_TITLE:-}""",
    "contact_tp_found": ${TP_FOUND},
    "contact_tp_id": """${TP_ID:-}""",
    "contact_tp_phone": """${TP_PHONE:-}""",
    "contact_tp_title": """${TP_TITLE:-}""",
    "call_found": ${CALL_FOUND},
    "call_id": """${CALL_ID:-}""",
    "call_subject": """${CALL_SUBJECT:-}""",
    "call_type": """${CALL_TYPE:-}""",
    "call_date": """${CALL_DATE:-}""",
    "call_start": """${CALL_START:-}""",
    "call_end": """${CALL_END:-}""",
    "call_status": """${CALL_STATUS:-}""",
    "task_start": ${TASK_START}
}

with open('/tmp/ironshield_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
