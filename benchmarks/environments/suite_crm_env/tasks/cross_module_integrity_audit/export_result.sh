#!/bin/bash
echo "=== Exporting cross_module_integrity_audit results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/cmi_final.png

suitecrm_db_query "SELECT id, name, account_type FROM accounts WHERE deleted=0 ORDER BY name" > /tmp/cmi_post_accounts.txt 2>/dev/null
suitecrm_db_query "SELECT id, first_name, last_name, account_id FROM contacts WHERE deleted=0 ORDER BY last_name" > /tmp/cmi_post_contacts.txt 2>/dev/null
chmod 666 /tmp/cmi_post_*.txt 2>/dev/null || true

echo "=== cross_module_integrity_audit export complete ==="
