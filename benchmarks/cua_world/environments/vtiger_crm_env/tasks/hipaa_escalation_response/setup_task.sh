#!/bin/bash
# Setup script for hipaa_escalation_response task
# Miscategorizes the HIPAA ticket and resets the deal stage to create
# a realistic "escalation needed" scenario.

echo "=== Setting up hipaa_escalation_response task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/hipaa_escalation_start_ts

# ---------------------------------------------------------------
# Miscategorize the HIPAA ticket:
# Change priority from Urgent → Normal, severity from Critical → Minor
# This is the "error" the agent must discover and fix.
# ---------------------------------------------------------------
vtiger_db_query "UPDATE vtiger_troubletickets SET priority='Normal', severity='Minor', status='Open' WHERE title='HIPAA audit finding - unencrypted backups'"
echo "Set HIPAA ticket to Normal priority / Minor severity / Open status (miscategorized)"

# ---------------------------------------------------------------
# Reset the Pinnacle EHR deal to wrong stage/probability
# The deal was Negotiation/Review at 80% — simulate it got downgraded
# ---------------------------------------------------------------
vtiger_db_query "UPDATE vtiger_potential SET sales_stage='Qualification', probability='30', closingdate='2026-07-30' WHERE potentialname='Pinnacle EHR Security Upgrade'"
echo "Reset Pinnacle EHR deal to Qualification/30%/2026-07-30"

# ---------------------------------------------------------------
# Remove any pre-existing HIPAA/Pinnacle meeting events (idempotent)
# This prevents seeded events from matching the export query.
# ---------------------------------------------------------------
vtiger_db_query "DELETE FROM vtiger_activity WHERE subject='HIPAA Emergency Remediation - Pinnacle Healthcare'" 2>/dev/null || true
vtiger_db_query "DELETE FROM vtiger_activity WHERE subject='Pinnacle HIPAA Remediation Kickoff'" 2>/dev/null || true

# Record initial event count
INITIAL_EVENT_COUNT=$(get_event_count)
echo "$INITIAL_EVENT_COUNT" > /tmp/hipaa_escalation_initial_event_count

# Navigate agent to support tickets list
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=HelpDesk&view=List"
sleep 3

take_screenshot /tmp/hipaa_escalation_start.png

echo "=== Setup Complete ==="
echo "Agent must: escalate ticket, update deal, create emergency meeting."
