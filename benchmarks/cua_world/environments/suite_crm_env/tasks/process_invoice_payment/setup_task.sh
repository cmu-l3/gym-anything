#!/bin/bash
set -e

echo "=== Setting up process_invoice_payment task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt 2>/dev/null || true

# Generate UUIDs for the seed data
ACC_ID=$(cat /proc/sys/kernel/random/uuid)
INV_ID=$(cat /proc/sys/kernel/random/uuid)

# Clean up any existing records with these names to ensure clean state
suitecrm_db_query "UPDATE notes SET deleted=1 WHERE name = 'Wire Transfer Confirmed'"
suitecrm_db_query "UPDATE aos_invoices SET deleted=1 WHERE name = 'INV-90950: Meridian Quarterly Supplies'"
suitecrm_db_query "UPDATE accounts SET deleted=1 WHERE name = 'Meridian Partners'"

# 1. Create the Account
suitecrm_db_query "INSERT INTO accounts (id, name, date_entered, date_modified, modified_user_id, created_by, deleted) VALUES ('${ACC_ID}', 'Meridian Partners', NOW(), NOW(), '1', '1', 0)"

# 2. Create the Unpaid Invoice linked to the Account
suitecrm_db_query "INSERT INTO aos_invoices (id, name, date_entered, date_modified, modified_user_id, created_by, deleted, status, total_amount, billing_account_id, invoice_date, due_date) VALUES ('${INV_ID}', 'INV-90950: Meridian Quarterly Supplies', NOW(), NOW(), '1', '1', 0, 'Unpaid', 14500.00, '${ACC_ID}', '2025-02-15', '2025-03-15')"

# Ensure user is logged in and on the home page
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 2

# Take initial screenshot
take_screenshot "/tmp/task_initial_state.png"

echo "=== Task setup complete ==="