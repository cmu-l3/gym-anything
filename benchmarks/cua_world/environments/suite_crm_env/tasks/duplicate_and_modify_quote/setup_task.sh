#!/bin/bash
echo "=== Setting up duplicate_and_modify_quote task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Clean up any existing test records
suitecrm_db_query "DELETE FROM accounts WHERE name='Pinnacle Distribution Co'"
suitecrm_db_query "DELETE FROM aos_quotes WHERE name LIKE 'Office Network Upgrade%'"
suitecrm_db_query "DELETE FROM aos_products_quotes WHERE parent_id='quote_phase1_123'"
suitecrm_db_query "DELETE FROM aos_line_item_groups WHERE parent_id='quote_phase1_123'"

# Insert Account
ACC_ID="acc_pinnacle_123"
suitecrm_db_query "INSERT INTO accounts (id, name, date_entered, date_modified, modified_user_id, created_by, deleted) VALUES ('$ACC_ID', 'Pinnacle Distribution Co', NOW(), NOW(), '1', '1', 0)"

# Insert original Quote
QUOTE_ID="quote_phase1_123"
TERMS="LEGAL DISCLAIMER: This quote is subject to the Master Services Agreement v4.2 signed on 01/15/2023. Any hardware returns are subject to a 15% restocking fee. Valid only for Pinnacle Distribution Co."
suitecrm_db_query "INSERT INTO aos_quotes (id, name, date_entered, date_modified, modified_user_id, created_by, deleted, billing_account_id, stage, expiration, term_conditions, total_amt, subtotal_amount) VALUES ('$QUOTE_ID', 'Office Network Upgrade - Phase 1', NOW(), NOW(), '1', '1', 0, '$ACC_ID', 'Closed Accepted', '2025-12-31', '$TERMS', 15000, 15000)"

# Insert Line Item Group
GROUP_ID="group_123"
suitecrm_db_query "INSERT INTO aos_line_item_groups (id, name, date_entered, date_modified, modified_user_id, created_by, deleted, parent_type, parent_id, number, total_amt) VALUES ('$GROUP_ID', 'Hardware', NOW(), NOW(), '1', '1', 0, 'AOS_Quotes', '$QUOTE_ID', 1, 15000)"

# Insert Line Items
LINE1_ID="line_router_123"
suitecrm_db_query "INSERT INTO aos_products_quotes (id, name, date_entered, date_modified, modified_user_id, created_by, deleted, product_qty, product_unit_price, product_total_price, parent_type, parent_id, group_id, item_description) VALUES ('$LINE1_ID', 'Cisco ISR 4331 Integrated Services Router', NOW(), NOW(), '1', '1', 0, 5, 1000, 5000, 'AOS_Quotes', '$QUOTE_ID', '$GROUP_ID', 'Cisco ISR 4331 Integrated Services Router')"

LINE2_ID="line_switch_123"
suitecrm_db_query "INSERT INTO aos_products_quotes (id, name, date_entered, date_modified, modified_user_id, created_by, deleted, product_qty, product_unit_price, product_total_price, parent_type, parent_id, group_id, item_description) VALUES ('$LINE2_ID', 'Cisco Catalyst 9300 48-port PoE+ Switch', NOW(), NOW(), '1', '1', 0, 10, 1000, 10000, 'AOS_Quotes', '$QUOTE_ID', '$GROUP_ID', 'Cisco Catalyst 9300 48-port PoE+ Switch')"

# Ensure logged in and navigate to Quotes module
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=AOS_Quotes&action=index"
sleep 3

# Take initial screenshot
take_screenshot /tmp/duplicate_quote_initial.png

echo "=== duplicate_and_modify_quote task setup complete ==="