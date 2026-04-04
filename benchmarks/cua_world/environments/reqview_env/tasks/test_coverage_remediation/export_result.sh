#!/bin/bash
echo "=== Exporting test_coverage_remediation Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot /tmp/test_coverage_end.png

echo "=== Export Complete ==="
