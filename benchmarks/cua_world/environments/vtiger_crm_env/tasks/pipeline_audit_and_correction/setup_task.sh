#!/bin/bash
# Setup script for pipeline_audit_and_correction task
# Injects data quality errors into the pipeline that the agent must discover and fix.

echo "=== Setting up pipeline_audit_and_correction task ==="

source /workspace/scripts/task_utils.sh

# Record baseline deal counts
INITIAL_DEAL_COUNT=$(get_deal_count)
echo "$INITIAL_DEAL_COUNT" > /tmp/pipeline_audit_initial_deal_count
date +%s > /tmp/pipeline_audit_start_ts

# ---------------------------------------------------------------
# Inject Error 1: Nexus SCADA Security Assessment
# Stage=Closed Won but set probability to 65 (should be 100)
# ---------------------------------------------------------------
vtiger_db_query "UPDATE vtiger_potential SET probability='65' WHERE potentialname='Nexus SCADA Security Assessment'"
echo "Injected Error 1: Nexus SCADA - probability set to 65 (Closed Won stage)"

# ---------------------------------------------------------------
# Inject Error 2: GreenLeaf IoT Factory Monitoring
# Stage=Needs Analysis but set probability to 88 (should be 20-50)
# ---------------------------------------------------------------
vtiger_db_query "UPDATE vtiger_potential SET probability='88' WHERE potentialname='GreenLeaf IoT Factory Monitoring'"
echo "Injected Error 2: GreenLeaf IoT - probability set to 88 (Needs Analysis stage)"

# ---------------------------------------------------------------
# Inject Error 3: Atlas Supply Chain Analytics
# Change closingdate to past (2025-06-30), stage stays Perception Analysis
# ---------------------------------------------------------------
vtiger_db_query "UPDATE vtiger_potential SET closingdate='2025-06-30' WHERE potentialname='Atlas Supply Chain Analytics'"
echo "Injected Error 3: Atlas Supply Chain - closingdate set to 2025-06-30 (stale)"

# ---------------------------------------------------------------
# Inject Error 4: Catalyst LIMS Implementation
# Change closingdate to past (2025-09-15), stage stays Needs Analysis
# ---------------------------------------------------------------
vtiger_db_query "UPDATE vtiger_potential SET closingdate='2025-09-15' WHERE potentialname='Catalyst LIMS Implementation'"
echo "Injected Error 4: Catalyst LIMS - closingdate set to 2025-09-15 (stale)"

# Verify injections
echo ""
echo "--- Verifying injections ---"
vtiger_db_query "SELECT potentialname, sales_stage, probability, closingdate FROM vtiger_potential WHERE potentialname IN ('Nexus SCADA Security Assessment','GreenLeaf IoT Factory Monitoring','Atlas Supply Chain Analytics','Catalyst LIMS Implementation')"

# Navigate agent to deals list
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Potentials&view=List"
sleep 3

take_screenshot /tmp/pipeline_audit_start.png

echo "=== Setup Complete ==="
echo "Injected 4 pipeline data quality errors for agent to discover and fix."
echo "Agent must also update Horizon 5G amount to 320000."
