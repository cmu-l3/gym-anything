#!/bin/bash
echo "=== Exporting crm_forensic_audit results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/cfa_final.png

# Snapshot current state for debugging
suitecrm_db_query "SELECT id, name, amount, sales_stage, probability, assigned_user_id, deleted FROM opportunities ORDER BY name" > /tmp/cfa_post_opps.txt 2>/dev/null
suitecrm_db_query "SELECT c.id, c.first_name, c.last_name, ac.account_id, c.deleted FROM contacts c LEFT JOIN accounts_contacts ac ON c.id=ac.contact_id AND ac.deleted=0 ORDER BY c.last_name" > /tmp/cfa_post_contacts.txt 2>/dev/null
chmod 666 /tmp/cfa_post_opps.txt /tmp/cfa_post_contacts.txt 2>/dev/null || true

echo "=== crm_forensic_audit export complete ==="
