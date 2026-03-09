#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Diagnose Slow Test Suite Result ==="

WORKSPACE_DIR="/home/ga/workspace/api-testing-project"
EXPORT_DIR="/tmp/test_suite_export"

mkdir -p "$EXPORT_DIR"

# Export the analysis report if it exists
if [ -f "$WORKSPACE_DIR/TEST_PERFORMANCE_ANALYSIS.md" ]; then
    cp "$WORKSPACE_DIR/TEST_PERFORMANCE_ANALYSIS.md" "$EXPORT_DIR/"
    echo "✅ Exported TEST_PERFORMANCE_ANALYSIS.md"
    
    # Also copy to /tmp root for easier verification access
    cp "$WORKSPACE_DIR/TEST_PERFORMANCE_ANALYSIS.md" /tmp/
else
    echo "⚠️ TEST_PERFORMANCE_ANALYSIS.md not found"
    echo "Report not created" > "$EXPORT_DIR/status.txt"
fi

# Export pytest output if agent saved it
if [ -f "$WORKSPACE_DIR/pytest_output.txt" ]; then
    cp "$WORKSPACE_DIR/pytest_output.txt" "$EXPORT_DIR/"
    echo "✅ Exported pytest output"
fi

# Export any notes or scratch files
find "$WORKSPACE_DIR" -maxdepth 1 -name "*.md" -o -name "*.txt" | while read file; do
    if [ -f "$file" ]; then
        cp "$file" "$EXPORT_DIR/" 2>/dev/null || true
    fi
done

# Create a summary
cat > "$EXPORT_DIR/export_summary.txt" << EOF
Export Summary
==============
Workspace: $WORKSPACE_DIR
Export Time: $(date)

Files exported:
$(ls -lh $EXPORT_DIR/)

Report exists: $([ -f "$WORKSPACE_DIR/TEST_PERFORMANCE_ANALYSIS.md" ] && echo "YES" || echo "NO")
EOF

echo "✅ Export complete: $EXPORT_DIR"
echo "Report location: /tmp/TEST_PERFORMANCE_ANALYSIS.md"