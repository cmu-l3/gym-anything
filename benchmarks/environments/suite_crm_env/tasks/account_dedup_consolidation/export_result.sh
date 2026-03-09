#!/bin/bash
echo "=== Exporting account_dedup_consolidation results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/adc_final.png

suitecrm_db_query "SELECT id, name, deleted FROM accounts ORDER BY name" > /tmp/adc_post_accounts.txt 2>/dev/null
suitecrm_db_query "SELECT id, first_name, last_name, account_id FROM contacts WHERE deleted=0 ORDER BY last_name" > /tmp/adc_post_contacts.txt 2>/dev/null
chmod 666 /tmp/adc_post_*.txt 2>/dev/null || true

echo "=== account_dedup_consolidation export complete ==="
