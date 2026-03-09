#!/bin/bash
echo "=== Exporting pipeline_discrepancy_audit results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/pda_final.png

# Snapshot current state for debugging
suitecrm_db_query "SELECT id, name, amount, sales_stage, deleted FROM opportunities ORDER BY name" > /tmp/pda_post_opps.txt 2>/dev/null
chmod 666 /tmp/pda_post_opps.txt 2>/dev/null || true

echo "=== pipeline_discrepancy_audit export complete ==="
