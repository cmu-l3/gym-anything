#!/bin/bash
# Export script for client_onboarding_full_setup task

echo "=== Exporting client_onboarding_full_setup results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/onboarding_final.png

TASK_START=$(cat /tmp/onboarding_start_ts 2>/dev/null || echo "0")

# --- Query Organization ---
ORG_DATA=$(vtiger_db_query "SELECT a.accountid, a.accountname, a.phone, a.website, a.employees, a.annual_revenue, b.bill_city, b.bill_state, b.bill_street FROM vtiger_account a LEFT JOIN vtiger_accountbillads b ON a.accountid=b.accountaddressid WHERE a.accountname='ClearSky Aerospace Technologies' LIMIT 1")
ORG_ID=$(echo "$ORG_DATA" | awk -F'\t' '{print $1}')
ORG_NAME=$(echo "$ORG_DATA" | awk -F'\t' '{print $2}')
ORG_PHONE=$(echo "$ORG_DATA" | awk -F'\t' '{print $3}')
ORG_WEBSITE=$(echo "$ORG_DATA" | awk -F'\t' '{print $4}')
ORG_EMPLOYEES=$(echo "$ORG_DATA" | awk -F'\t' '{print $5}')
ORG_REVENUE=$(echo "$ORG_DATA" | awk -F'\t' '{print $6}')
ORG_CITY=$(echo "$ORG_DATA" | awk -F'\t' '{print $7}')
ORG_STATE=$(echo "$ORG_DATA" | awk -F'\t' '{print $8}')

ORG_FOUND="False"
[ -n "$ORG_ID" ] && ORG_FOUND="True"

# --- Query Contact A: Harrison Yates ---
CONTACT_A_DATA=$(vtiger_db_query "SELECT contactid, firstname, lastname, email, phone, title FROM vtiger_contactdetails WHERE firstname='Harrison' AND lastname='Yates' LIMIT 1")
CONTACT_A_ID=$(echo "$CONTACT_A_DATA" | awk -F'\t' '{print $1}')
CONTACT_A_EMAIL=$(echo "$CONTACT_A_DATA" | awk -F'\t' '{print $4}')
CONTACT_A_PHONE=$(echo "$CONTACT_A_DATA" | awk -F'\t' '{print $5}')
CONTACT_A_TITLE=$(echo "$CONTACT_A_DATA" | awk -F'\t' '{print $6}')

CONTACT_A_FOUND="False"
[ -n "$CONTACT_A_ID" ] && CONTACT_A_FOUND="True"

# --- Query Contact B: Priya Natarajan ---
CONTACT_B_DATA=$(vtiger_db_query "SELECT contactid, firstname, lastname, email, phone, title FROM vtiger_contactdetails WHERE firstname='Priya' AND lastname='Natarajan' LIMIT 1")
CONTACT_B_ID=$(echo "$CONTACT_B_DATA" | awk -F'\t' '{print $1}')
CONTACT_B_EMAIL=$(echo "$CONTACT_B_DATA" | awk -F'\t' '{print $4}')
CONTACT_B_PHONE=$(echo "$CONTACT_B_DATA" | awk -F'\t' '{print $5}')
CONTACT_B_TITLE=$(echo "$CONTACT_B_DATA" | awk -F'\t' '{print $6}')

CONTACT_B_FOUND="False"
[ -n "$CONTACT_B_ID" ] && CONTACT_B_FOUND="True"

# Check contact-org linkage (contacts should be linked to ClearSky)
CONTACT_A_ORG_LINKED="False"
CONTACT_B_ORG_LINKED="False"
if [ -n "$ORG_ID" ] && [ -n "$CONTACT_A_ID" ]; then
    LINK=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_contactdetails WHERE contactid='$CONTACT_A_ID' AND account_id='$ORG_ID'" | tr -d '[:space:]')
    [ "${LINK:-0}" -gt 0 ] && CONTACT_A_ORG_LINKED="True"
fi
if [ -n "$ORG_ID" ] && [ -n "$CONTACT_B_ID" ]; then
    LINK=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_contactdetails WHERE contactid='$CONTACT_B_ID' AND account_id='$ORG_ID'" | tr -d '[:space:]')
    [ "${LINK:-0}" -gt 0 ] && CONTACT_B_ORG_LINKED="True"
fi

# --- Query Deal ---
DEAL_DATA=$(vtiger_db_query "SELECT potentialid, potentialname, amount, sales_stage, probability, closingdate FROM vtiger_potential WHERE potentialname='ClearSky Zero-Trust Security Implementation' LIMIT 1")
DEAL_ID=$(echo "$DEAL_DATA" | awk -F'\t' '{print $1}')
DEAL_NAME=$(echo "$DEAL_DATA" | awk -F'\t' '{print $2}')
DEAL_AMOUNT=$(echo "$DEAL_DATA" | awk -F'\t' '{print $3}')
DEAL_STAGE=$(echo "$DEAL_DATA" | awk -F'\t' '{print $4}')
DEAL_PROB=$(echo "$DEAL_DATA" | awk -F'\t' '{print $5}')
DEAL_DATE=$(echo "$DEAL_DATA" | awk -F'\t' '{print $6}')

DEAL_FOUND="False"
[ -n "$DEAL_ID" ] && DEAL_FOUND="True"

# --- Query Meeting Event ---
EVENT_DATA=$(vtiger_db_query "SELECT activityid, subject, activitytype, date_start, time_start, time_end, status, location FROM vtiger_activity WHERE subject LIKE '%ClearSky%Kickoff%' OR subject LIKE '%ClearSky%Onboarding%' ORDER BY activityid DESC LIMIT 1")
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
    "org_found": ${ORG_FOUND},
    "org_id": """${ORG_ID:-}""",
    "org_name": """${ORG_NAME:-}""",
    "org_phone": """${ORG_PHONE:-}""",
    "org_website": """${ORG_WEBSITE:-}""",
    "org_employees": """${ORG_EMPLOYEES:-}""",
    "org_revenue": """${ORG_REVENUE:-}""",
    "org_city": """${ORG_CITY:-}""",
    "org_state": """${ORG_STATE:-}""",
    "contact_a_found": ${CONTACT_A_FOUND},
    "contact_a_id": """${CONTACT_A_ID:-}""",
    "contact_a_email": """${CONTACT_A_EMAIL:-}""",
    "contact_a_phone": """${CONTACT_A_PHONE:-}""",
    "contact_a_title": """${CONTACT_A_TITLE:-}""",
    "contact_a_org_linked": ${CONTACT_A_ORG_LINKED},
    "contact_b_found": ${CONTACT_B_FOUND},
    "contact_b_id": """${CONTACT_B_ID:-}""",
    "contact_b_email": """${CONTACT_B_EMAIL:-}""",
    "contact_b_phone": """${CONTACT_B_PHONE:-}""",
    "contact_b_title": """${CONTACT_B_TITLE:-}""",
    "contact_b_org_linked": ${CONTACT_B_ORG_LINKED},
    "deal_found": ${DEAL_FOUND},
    "deal_id": """${DEAL_ID:-}""",
    "deal_name": """${DEAL_NAME:-}""",
    "deal_amount": """${DEAL_AMOUNT:-}""",
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
    "task_start": ${TASK_START}
}

with open('/tmp/onboarding_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
