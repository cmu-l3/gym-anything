#!/bin/bash
# Setup script for create_ap_invoice task
echo "=== Setting up create_ap_invoice ==="

source /workspace/scripts/task_utils.sh

# Record baseline count of vendor invoices for Tree Farm Inc. (c_bpartner_id=114)
INITIAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_invoice WHERE ad_client_id=11 AND c_bpartner_id=114 AND issotrx='N'")
INITIAL_COUNT=${INITIAL_COUNT:-0}
echo "Initial Tree Farm Inc. vendor invoice count: $INITIAL_COUNT"
echo "$INITIAL_COUNT" > /tmp/initial_treefarm_invoice_count

# Record existing invoice IDs to detect new ones
idempiere_query "SELECT c_invoice_id FROM c_invoice WHERE ad_client_id=11 AND c_bpartner_id=114 AND issotrx='N' ORDER BY c_invoice_id" > /tmp/initial_treefarm_invoice_ids

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Navigate to dashboard
navigate_to_dashboard

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
