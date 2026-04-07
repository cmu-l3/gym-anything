#!/bin/bash
# Setup script for configure_customer_credit_and_order task
echo "=== Setting up configure_customer_credit_and_order ==="

source /workspace/scripts/task_utils.sh

# Reset Agri-Tech (c_bpartner_id=200000) to a known initial state:
# so_creditlimit=5000, payment terms=Immediate (105)
# This simulates the account before the credit review was approved.
idempiere_query "UPDATE c_bpartner SET so_creditlimit=5000, c_paymentterm_id=105, updated=NOW(), updatedby=100 WHERE c_bpartner_id=200000 AND ad_client_id=11"

# Record the initial state
INIT_CREDIT=$(idempiere_query "SELECT so_creditlimit FROM c_bpartner WHERE c_bpartner_id=200000 AND ad_client_id=11")
INIT_PAYTERM=$(idempiere_query "SELECT c_paymentterm_id FROM c_bpartner WHERE c_bpartner_id=200000 AND ad_client_id=11")
INIT_CREDIT=${INIT_CREDIT:-5000}
INIT_PAYTERM=${INIT_PAYTERM:-105}

echo "Initial state — creditlimit: $INIT_CREDIT | paymentterm_id: $INIT_PAYTERM"
echo "${INIT_CREDIT}|${INIT_PAYTERM}" > /tmp/initial_agritech_settings

# Record existing Sales Orders for Agri-Tech (baseline)
idempiere_query "SELECT c_order_id FROM c_order WHERE ad_client_id=11 AND c_bpartner_id=200000 AND issotrx='Y' ORDER BY c_order_id" > /tmp/initial_agritech_so_ids

INIT_SO_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_order WHERE ad_client_id=11 AND c_bpartner_id=200000 AND issotrx='Y'")
echo "Initial Agri-Tech SO count: ${INIT_SO_COUNT:-0}"
echo "${INIT_SO_COUNT:-0}" > /tmp/initial_agritech_so_count

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Navigate to dashboard
navigate_to_dashboard

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
