#!/bin/bash
echo "=== Exporting p1_escalation_workflow results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/p1e_final.png

suitecrm_db_query "SELECT id, name, status, priority, description FROM cases WHERE deleted=0 ORDER BY name" > /tmp/p1e_post_cases.txt 2>/dev/null
chmod 666 /tmp/p1e_post_cases.txt 2>/dev/null || true

echo "=== p1_escalation_workflow export complete ==="
