#!/bin/bash
# Setup script for stale_pipeline_and_ticket_cleanup task

echo "=== Setting up stale_pipeline_and_ticket_cleanup ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/crm_cleanup_start_ts

# -----------------------------------------------------------------------
# 1. Inject stale closing dates into active deals so they appear overdue.
#    The agent must audit the full pipeline and discover these.
#    Today is 2026-03-07 (task context date), so use past dates.
# -----------------------------------------------------------------------
echo "Injecting stale closing dates into active deals..."

# Stale deal 1: Nexus SCADA Security Assessment — currently active, inject past close date
vtiger_db_query "UPDATE vtiger_potential SET closingdate='2025-11-30' WHERE potentialname='Nexus SCADA Security Assessment' AND sales_stage NOT IN ('Closed Won','Closed Lost')"

# Stale deal 2: Atlas Supply Chain Analytics — currently active, inject past close date
vtiger_db_query "UPDATE vtiger_potential SET closingdate='2025-09-15' WHERE potentialname='Atlas Supply Chain Analytics' AND sales_stage NOT IN ('Closed Won','Closed Lost')"

# -----------------------------------------------------------------------
# 2. Inject ticket hygiene issue:
#    Find a high-severity ticket and set it to 'Closed' status (wrong).
#    The agent must find tickets that are Closed but Critical/Urgent
#    and reclassify them to Resolved.
# -----------------------------------------------------------------------
echo "Injecting misclosed critical ticket..."
TICKET_ID=$(vtiger_db_query "SELECT ticketid FROM vtiger_troubletickets WHERE ticket_title LIKE '%breach%' OR ticket_title LIKE '%incident%' OR ticket_title LIKE '%Data%' LIMIT 1" | tr -d '[:space:]')

if [ -n "$TICKET_ID" ]; then
    # Set status=Closed, severity=Critical, priority=Urgent — this is the misclosed ticket
    vtiger_db_query "UPDATE vtiger_troubletickets SET ticketstatus='Closed', ticketseverities='Critical', ticketpriorities='Urgent' WHERE ticketid='$TICKET_ID'"
    echo "Injected: ticket $TICKET_ID set to Closed+Critical+Urgent"
else
    # If no matching ticket found, pick any ticket and corrupt it
    ANY_TICKET=$(vtiger_db_query "SELECT ticketid FROM vtiger_troubletickets LIMIT 1" | tr -d '[:space:]')
    if [ -n "$ANY_TICKET" ]; then
        vtiger_db_query "UPDATE vtiger_troubletickets SET ticketstatus='Closed', ticketseverities='Critical', ticketpriorities='Urgent' WHERE ticketid='$ANY_TICKET'"
        echo "Fallback: ticket $ANY_TICKET set to Closed+Critical+Urgent"
    fi
fi

# -----------------------------------------------------------------------
# 3. Clear Blackstone Industrial industry and description fields
# -----------------------------------------------------------------------
echo "Clearing Blackstone Industrial industry/description..."
ACCT_ID=$(vtiger_db_query "SELECT accountid FROM vtiger_account WHERE accountname='Blackstone Industrial' LIMIT 1" | tr -d '[:space:]')
if [ -n "$ACCT_ID" ]; then
    vtiger_db_query "UPDATE vtiger_account SET industry='', description='' WHERE accountid='$ACCT_ID'"
    echo "Cleared Blackstone Industrial fields"
else
    echo "WARNING: Blackstone Industrial account not found"
fi

# -----------------------------------------------------------------------
# 4. Record baseline counts for verification delta
# -----------------------------------------------------------------------
STALE_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_potential WHERE closingdate < CURDATE() AND sales_stage NOT IN ('Closed Won','Closed Lost')" | tr -d '[:space:]')
echo "$STALE_COUNT" > /tmp/crm_cleanup_baseline_stale_count

MISCLOSED_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_troubletickets WHERE ticketstatus='Closed' AND (ticketseverities='Critical' OR ticketpriorities='Urgent')" | tr -d '[:space:]')
echo "$MISCLOSED_COUNT" > /tmp/crm_cleanup_baseline_misclosed_count

# -----------------------------------------------------------------------
# 5. Navigate agent to dashboard/home to start auditing
# -----------------------------------------------------------------------
ensure_vtiger_logged_in

take_screenshot /tmp/crm_cleanup_setup_done.png

echo "=== Setup complete: stale deals injected, misclosed ticket injected, Blackstone fields cleared ==="
echo "=== Stale deals requiring cleanup: $STALE_COUNT ==="
echo "=== Misclosed critical tickets: $MISCLOSED_COUNT ==="
