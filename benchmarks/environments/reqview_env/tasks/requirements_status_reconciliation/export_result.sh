#!/bin/bash
echo "=== Exporting requirements_status_reconciliation Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot /tmp/status_reconciliation_end.png

echo "=== Export Complete ==="
