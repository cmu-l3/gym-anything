#!/bin/bash
echo "=== Exporting v2_verification_traceability_audit Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot /tmp/v2_audit_end.png

echo "=== Export Complete ==="
