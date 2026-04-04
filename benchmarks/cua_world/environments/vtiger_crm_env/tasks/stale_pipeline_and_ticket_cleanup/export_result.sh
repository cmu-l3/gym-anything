#!/bin/bash
# Export script for stale_pipeline_and_ticket_cleanup task

echo "=== Exporting stale_pipeline_and_ticket_cleanup results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/crm_cleanup_final.png

TASK_START=$(cat /tmp/crm_cleanup_start_ts 2>/dev/null || echo "0")

# --- Query: How many stale deals still remain (active + past close date)? ---
REMAINING_STALE=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_potential WHERE closingdate < CURDATE() AND sales_stage NOT IN ('Closed Won','Closed Lost')" | tr -d '[:space:]')

# --- Query specific target deals (were they closed?) ---
NEXUS_DATA=$(vtiger_db_query "SELECT potentialid, potentialname, sales_stage, probability, closingdate FROM vtiger_potential WHERE potentialname='Nexus SCADA Security Assessment' LIMIT 1")
NEXUS_STAGE=$(echo "$NEXUS_DATA" | awk -F'\t' '{print $3}')
NEXUS_PROB=$(echo "$NEXUS_DATA" | awk -F'\t' '{print $4}')

ATLAS_DATA=$(vtiger_db_query "SELECT potentialid, potentialname, sales_stage, probability, closingdate FROM vtiger_potential WHERE potentialname='Atlas Supply Chain Analytics' LIMIT 1")
ATLAS_STAGE=$(echo "$ATLAS_DATA" | awk -F'\t' '{print $3}')
ATLAS_PROB=$(echo "$ATLAS_DATA" | awk -F'\t' '{print $4}')

# --- Query: Any tickets still in Closed+Critical/Urgent state? ---
STILL_MISCLOSED=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_troubletickets WHERE ticketstatus='Closed' AND (ticketseverities='Critical' OR ticketpriorities='Urgent')" | tr -d '[:space:]')

# --- Query: Find tickets now in Resolved state with SLA audit note ---
RESOLVED_TICKET_DATA=$(vtiger_db_query "SELECT ticketid, ticket_title, ticketstatus, ticketseverities, ticketpriorities, description FROM vtiger_troubletickets WHERE ticketstatus='Resolved' AND (ticketseverities='Critical' OR ticketpriorities='Urgent') ORDER BY ticketid DESC LIMIT 5")
RESOLVED_TICKET_COUNT=$(echo "$RESOLVED_TICKET_DATA" | grep -c 'Resolved' || echo "0")

# Check if any resolved ticket has the SLA-AUDIT marker
SLA_AUDIT_TICKET=$(vtiger_db_query "SELECT ticketid, ticket_title, description FROM vtiger_troubletickets WHERE description LIKE '%SLA-AUDIT%' LIMIT 1")
SLA_TICKET_ID=$(echo "$SLA_AUDIT_TICKET" | awk -F'\t' '{print $1}')
SLA_TICKET_TITLE=$(echo "$SLA_AUDIT_TICKET" | awk -F'\t' '{print $2}')
SLA_TICKET_DESC=$(echo "$SLA_AUDIT_TICKET" | awk -F'\t' '{print $3}')

SLA_TICKET_FOUND="False"
[ -n "$SLA_TICKET_ID" ] && SLA_TICKET_FOUND="True"

# --- Query Blackstone Industrial account ---
ACCT_DATA=$(vtiger_db_query "SELECT accountid, accountname, industry, description FROM vtiger_account WHERE accountname='Blackstone Industrial' LIMIT 1")
ACCT_ID=$(echo "$ACCT_DATA" | awk -F'\t' '{print $1}')
ACCT_INDUSTRY=$(echo "$ACCT_DATA" | awk -F'\t' '{print $3}')
ACCT_DESC=$(echo "$ACCT_DATA" | awk -F'\t' '{print $4}')

ACCT_FOUND="False"
[ -n "$ACCT_ID" ] && ACCT_FOUND="True"

python3 << PYEOF
import json

result = {
    "remaining_stale_deals": int("${REMAINING_STALE:-0}" or "0"),
    "nexus_stage": """${NEXUS_STAGE:-}""",
    "nexus_probability": """${NEXUS_PROB:-}""",
    "atlas_stage": """${ATLAS_STAGE:-}""",
    "atlas_probability": """${ATLAS_PROB:-}""",
    "still_misclosed_critical_tickets": int("${STILL_MISCLOSED:-0}" or "0"),
    "sla_audit_ticket_found": ${SLA_TICKET_FOUND},
    "sla_ticket_id": """${SLA_TICKET_ID:-}""",
    "sla_ticket_title": """${SLA_TICKET_TITLE:-}""",
    "sla_ticket_desc_snippet": """${SLA_TICKET_DESC:-}"""[:200],
    "account_found": ${ACCT_FOUND},
    "account_industry": """${ACCT_INDUSTRY:-}""",
    "account_description": """${ACCT_DESC:-}""",
    "task_start": ${TASK_START}
}

with open('/tmp/crm_cleanup_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
