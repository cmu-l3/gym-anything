#!/bin/bash
echo "=== Exporting risk_assessment_remediation Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot /tmp/risk_assessment_end.png

echo "=== Export Complete ==="
