#!/bin/bash
echo "=== Exporting stale_pipeline_cleanup results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/spc_final.png

suitecrm_db_query "SELECT id, name, sales_stage, probability, date_closed FROM opportunities WHERE deleted=0 ORDER BY name" > /tmp/spc_post_opps.txt 2>/dev/null
chmod 666 /tmp/spc_post_opps.txt 2>/dev/null || true

echo "=== stale_pipeline_cleanup export complete ==="
