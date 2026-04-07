#!/bin/bash
# Setup script for quarterly_pipeline_reconciliation_with_ticket_crossref task
#
# Injects support tickets linked to specific Organizations and adjusts deal
# close dates to create a realistic quarterly pipeline reconciliation scenario.
#
# The agent must discover which deals are affected by cross-referencing
# the Potentials module against the HelpDesk (tickets) module.

echo "=== Setting up quarterly_pipeline_reconciliation_with_ticket_crossref ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/reconciliation_start_ts

# ---------------------------------------------------------------
# Step 1: Idempotent cleanup — remove tickets from previous runs
# ---------------------------------------------------------------
echo "Cleaning up any previous reconciliation tickets..."
for TKT_NO in TT-REC-001 TT-REC-002 TT-REC-003 TT-REC-004 TT-REC-005; do
    OLD_ID=$(vtiger_db_query "SELECT ticketid FROM vtiger_troubletickets WHERE ticket_no='$TKT_NO' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$OLD_ID" ]; then
        vtiger_db_query "DELETE FROM vtiger_ticketcf WHERE ticketid=$OLD_ID"
        vtiger_db_query "DELETE FROM vtiger_troubletickets WHERE ticketid=$OLD_ID"
        vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$OLD_ID"
        echo "  Removed old ticket $TKT_NO (ID: $OLD_ID)"
    fi
done

# ---------------------------------------------------------------
# Step 2: Neutralize existing Critical/Major open tickets
# Close ALL existing open Critical/Major tickets so only our injected
# tickets determine the reconciliation outcomes (deterministic).
# ---------------------------------------------------------------
echo "Closing all existing open Critical/Major tickets..."
vtiger_db_query "UPDATE vtiger_troubletickets SET status='Closed' WHERE severity IN ('Critical','Major') AND status IN ('Open','In Progress','Waiting For Response')"

# ---------------------------------------------------------------
# Step 3: Normalize deal probabilities for Major-impact targets
# Set known starting probabilities so the -20pt reduction is deterministic.
# ---------------------------------------------------------------
echo "Normalizing deal probabilities..."
vtiger_db_query "UPDATE vtiger_potential SET probability=40 WHERE potentialname='GreenLeaf IoT Factory Monitoring'"
vtiger_db_query "UPDATE vtiger_potential SET probability=70 WHERE potentialname='Sterling Trading Platform Modernization'"

# ---------------------------------------------------------------
# Step 4: Set past-due close dates (Rule 1 targets)
# These deals will be auto-closed by the agent.
# ---------------------------------------------------------------
echo "Setting past-due close dates..."
vtiger_db_query "UPDATE vtiger_potential SET closingdate='2026-02-15' WHERE potentialname='BrightPath LMS Platform Build'"
vtiger_db_query "UPDATE vtiger_potential SET closingdate='2026-01-30' WHERE potentialname='Catalyst LIMS Implementation'"

# ---------------------------------------------------------------
# Step 5: Ensure all other open deals have future close dates
# This prevents false positives from Rule 1.
# ---------------------------------------------------------------
echo "Setting future close dates for non-target open deals..."
vtiger_db_query "UPDATE vtiger_potential SET closingdate='2026-06-30' WHERE potentialname IN (
    'Apex Cloud Migration Phase 2',
    'Pinnacle EHR Security Upgrade',
    'Sterling Trading Platform Modernization',
    'GreenLeaf IoT Factory Monitoring',
    'Atlas Supply Chain Analytics',
    'Horizon 5G Network Planning',
    'Coastal Retail E-Commerce Replatform',
    'Ironclad Claims AI Platform'
) AND sales_stage NOT IN ('Closed Won','Closed Lost')"

# ---------------------------------------------------------------
# Step 6: Clear descriptions of all open deals
# Ensures audit tags are unambiguous (no leftover text from other tasks).
# Description is stored in vtiger_crmentity.description, not vtiger_potential.
# ---------------------------------------------------------------
echo "Clearing descriptions on open deals..."
vtiger_db_query "UPDATE vtiger_crmentity SET description='' WHERE setype='Potentials' AND crmid IN (SELECT potentialid FROM vtiger_potential WHERE sales_stage NOT IN ('Closed Won','Closed Lost'))"

# ---------------------------------------------------------------
# Step 7: Record baseline state of "clean" deals
# These deals should NOT be modified by the agent.
# ---------------------------------------------------------------
echo "Recording baseline state for clean deals..."
APEX_BASELINE=$(vtiger_db_query "SELECT sales_stage, probability FROM vtiger_potential WHERE potentialname='Apex Cloud Migration Phase 2' LIMIT 1")
HORIZON_BASELINE=$(vtiger_db_query "SELECT sales_stage, probability FROM vtiger_potential WHERE potentialname='Horizon 5G Network Planning' LIMIT 1")
COASTAL_BASELINE=$(vtiger_db_query "SELECT sales_stage, probability FROM vtiger_potential WHERE potentialname='Coastal Retail E-Commerce Replatform' LIMIT 1")
IRONCLAD_BASELINE=$(vtiger_db_query "SELECT sales_stage, probability FROM vtiger_potential WHERE potentialname='Ironclad Claims AI Platform' LIMIT 1")

python3 << PYEOF
import json
baselines = {
    "apex": {
        "stage": """$(echo "$APEX_BASELINE" | awk -F'\t' '{print $1}')""".strip(),
        "probability": """$(echo "$APEX_BASELINE" | awk -F'\t' '{print $2}')""".strip()
    },
    "horizon": {
        "stage": """$(echo "$HORIZON_BASELINE" | awk -F'\t' '{print $1}')""".strip(),
        "probability": """$(echo "$HORIZON_BASELINE" | awk -F'\t' '{print $2}')""".strip()
    },
    "coastal": {
        "stage": """$(echo "$COASTAL_BASELINE" | awk -F'\t' '{print $1}')""".strip(),
        "probability": """$(echo "$COASTAL_BASELINE" | awk -F'\t' '{print $2}')""".strip()
    },
    "ironclad": {
        "stage": """$(echo "$IRONCLAD_BASELINE" | awk -F'\t' '{print $1}')""".strip(),
        "probability": """$(echo "$IRONCLAD_BASELINE" | awk -F'\t' '{print $2}')""".strip()
    }
}
with open('/tmp/reconciliation_baselines.json', 'w') as f:
    json.dump(baselines, f, indent=2)
print("Baselines saved:", json.dumps(baselines))
PYEOF

# ---------------------------------------------------------------
# Step 8: Helper to get next CRM entity ID
# ---------------------------------------------------------------
get_next_crmid() {
    vtiger_db_query "UPDATE vtiger_crmentity_seq SET id = id + 1"
    vtiger_db_query "SELECT id FROM vtiger_crmentity_seq" | tr -d '[:space:]'
}

# ---------------------------------------------------------------
# Step 9: Look up Organization IDs for ticket linking
# ---------------------------------------------------------------
echo "Looking up organization IDs..."
ATLAS_ACCT_ID=$(vtiger_db_query "SELECT accountid FROM vtiger_account WHERE accountname='Atlas Logistics Corp' LIMIT 1" | tr -d '[:space:]')
PINNACLE_ACCT_ID=$(vtiger_db_query "SELECT accountid FROM vtiger_account WHERE accountname='Pinnacle Healthcare Systems' LIMIT 1" | tr -d '[:space:]')
GREENLEAF_ACCT_ID=$(vtiger_db_query "SELECT accountid FROM vtiger_account WHERE accountname='GreenLeaf Manufacturing' LIMIT 1" | tr -d '[:space:]')
STERLING_ACCT_ID=$(vtiger_db_query "SELECT accountid FROM vtiger_account WHERE accountname='Sterling Financial Group' LIMIT 1" | tr -d '[:space:]')

echo "  Atlas=$ATLAS_ACCT_ID, Pinnacle=$PINNACLE_ACCT_ID, GreenLeaf=$GREENLEAF_ACCT_ID, Sterling=$STERLING_ACCT_ID"

# Verify all org IDs were found
if [ -z "$ATLAS_ACCT_ID" ] || [ -z "$PINNACLE_ACCT_ID" ] || [ -z "$GREENLEAF_ACCT_ID" ] || [ -z "$STERLING_ACCT_ID" ]; then
    echo "ERROR: One or more organization IDs not found. Aborting."
    exit 1
fi

# ---------------------------------------------------------------
# Step 10: Inject Critical tickets (Rule 2 targets)
# ---------------------------------------------------------------
echo "Injecting Critical tickets..."

# --- Critical ticket for Atlas Logistics Corp ---
TKT1_ID=$(get_next_crmid)
vtiger_db_query "INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, modifiedby, setype, description, createdtime, modifiedtime, presence, deleted, label) VALUES ($TKT1_ID, 1, 1, 1, 'HelpDesk', 'All fleet GPS units reporting offline since March 17. Dispatch unable to track 47 active delivery vehicles across 3 regional hubs.', NOW(), NOW(), 1, 0, 'CRITICAL: Fleet GPS tracking system - complete outage since 03/17')"
vtiger_db_query "INSERT INTO vtiger_troubletickets (ticketid, ticket_no, title, parent_id, priority, severity, status) VALUES ($TKT1_ID, 'TT-REC-001', 'CRITICAL: Fleet GPS tracking system - complete outage since 03/17', $ATLAS_ACCT_ID, 'Urgent', 'Critical', 'Open')"
vtiger_db_query "INSERT INTO vtiger_ticketcf (ticketid) VALUES ($TKT1_ID)"
echo "  Created TT-REC-001: Critical ticket for Atlas Logistics (ID: $TKT1_ID)"

# --- Critical ticket for Pinnacle Healthcare Systems ---
TKT2_ID=$(get_next_crmid)
vtiger_db_query "INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, modifiedby, setype, description, createdtime, modifiedtime, presence, deleted, label) VALUES ($TKT2_ID, 1, 1, 1, 'HelpDesk', 'Patient records not syncing between EHR modules since March 16. Three-day data gap affecting 2400 patient records across 8 departments. HIPAA compliance risk flagged.', NOW(), NOW(), 1, 0, 'CRITICAL: EHR patient data sync failure - 72hr data gap')"
vtiger_db_query "INSERT INTO vtiger_troubletickets (ticketid, ticket_no, title, parent_id, priority, severity, status) VALUES ($TKT2_ID, 'TT-REC-002', 'CRITICAL: EHR patient data sync failure - 72hr data gap', $PINNACLE_ACCT_ID, 'Urgent', 'Critical', 'Open')"
vtiger_db_query "INSERT INTO vtiger_ticketcf (ticketid) VALUES ($TKT2_ID)"
echo "  Created TT-REC-002: Critical ticket for Pinnacle Healthcare (ID: $TKT2_ID)"

# ---------------------------------------------------------------
# Step 11: Inject Major tickets (Rule 3 targets)
# ---------------------------------------------------------------
echo "Injecting Major tickets..."

# --- Major ticket for GreenLeaf Manufacturing ---
TKT3_ID=$(get_next_crmid)
vtiger_db_query "INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, modifiedby, setype, description, createdtime, modifiedtime, presence, deleted, label) VALUES ($TKT3_ID, 1, 1, 1, 'HelpDesk', 'Sensors on Line 3 drifting beyond tolerance since last firmware update. QA rejection rate increased 15 percent.', NOW(), NOW(), 1, 0, 'Production line IoT sensor calibration drift affecting QA')"
vtiger_db_query "INSERT INTO vtiger_troubletickets (ticketid, ticket_no, title, parent_id, priority, severity, status) VALUES ($TKT3_ID, 'TT-REC-003', 'Production line IoT sensor calibration drift affecting QA', $GREENLEAF_ACCT_ID, 'High', 'Major', 'Open')"
vtiger_db_query "INSERT INTO vtiger_ticketcf (ticketid) VALUES ($TKT3_ID)"
echo "  Created TT-REC-003: Major ticket for GreenLeaf Manufacturing (ID: $TKT3_ID)"

# --- Major ticket for Sterling Financial Group ---
TKT4_ID=$(get_next_crmid)
vtiger_db_query "INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, modifiedby, setype, description, createdtime, modifiedtime, presence, deleted, label) VALUES ($TKT4_ID, 1, 1, 1, 'HelpDesk', 'Compliance module throwing errors after February platform update. Manual workaround in place but quarterly SEC filing deadline approaching.', NOW(), NOW(), 1, 0, 'Quarterly compliance report generation failing since Feb update')"
vtiger_db_query "INSERT INTO vtiger_troubletickets (ticketid, ticket_no, title, parent_id, priority, severity, status) VALUES ($TKT4_ID, 'TT-REC-004', 'Quarterly compliance report generation failing since Feb update', $STERLING_ACCT_ID, 'High', 'Major', 'In Progress')"
vtiger_db_query "INSERT INTO vtiger_ticketcf (ticketid) VALUES ($TKT4_ID)"
echo "  Created TT-REC-004: Major ticket for Sterling Financial (ID: $TKT4_ID)"

# --- Additional Major ticket for Atlas Logistics (precedence test) ---
# Atlas has BOTH a Critical and a Major ticket.
# The agent must correctly apply Rule 2 (Critical), not Rule 3 (Major).
TKT5_ID=$(get_next_crmid)
vtiger_db_query "INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, modifiedby, setype, description, createdtime, modifiedtime, presence, deleted, label) VALUES ($TKT5_ID, 1, 1, 1, 'HelpDesk', 'New firmware v3.2 causing intermittent scan failures on 40 percent of warehouse scanners. Workaround deployed but throughput reduced.', NOW(), NOW(), 1, 0, 'Warehouse barcode scanner firmware incompatibility')"
vtiger_db_query "INSERT INTO vtiger_troubletickets (ticketid, ticket_no, title, parent_id, priority, severity, status) VALUES ($TKT5_ID, 'TT-REC-005', 'Warehouse barcode scanner firmware incompatibility', $ATLAS_ACCT_ID, 'Normal', 'Major', 'Open')"
vtiger_db_query "INSERT INTO vtiger_ticketcf (ticketid) VALUES ($TKT5_ID)"
echo "  Created TT-REC-005: Major ticket for Atlas Logistics (ID: $TKT5_ID)"

# ---------------------------------------------------------------
# Step 12: Verify setup state
# ---------------------------------------------------------------
echo ""
echo "--- Verifying setup state ---"
echo "Past-due deals:"
vtiger_db_query "SELECT potentialname, closingdate, sales_stage, probability FROM vtiger_potential WHERE potentialname IN ('BrightPath LMS Platform Build','Catalyst LIMS Implementation')"
echo ""
echo "Injected tickets:"
vtiger_db_query "SELECT ticket_no, title, parent_id, severity, status FROM vtiger_troubletickets WHERE ticket_no LIKE 'TT-REC-%' ORDER BY ticket_no"
echo ""
echo "Open deals (not Closed Won/Lost) count:"
vtiger_db_query "SELECT COUNT(*) FROM vtiger_potential WHERE sales_stage NOT IN ('Closed Won','Closed Lost')"

# ---------------------------------------------------------------
# Step 13: Navigate agent to Potentials (Deals) list view
# ---------------------------------------------------------------
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Potentials&view=List"
sleep 3

take_screenshot /tmp/reconciliation_start.png

echo ""
echo "=== Setup Complete ==="
echo "Injected: 5 tickets (2 Critical for Atlas+Pinnacle, 3 Major for GreenLeaf+Sterling+Atlas)"
echo "Modified: 2 past-due close dates (BrightPath, Catalyst)"
echo "Normalized: 2 probabilities (GreenLeaf=40%, Sterling=70%)"
echo "Cleared: all open deal descriptions"
echo "Agent starts at: Potentials list view"
