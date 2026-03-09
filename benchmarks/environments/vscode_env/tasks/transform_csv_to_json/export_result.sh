#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting CSV to JSON Transformation Result ==="

WORKSPACE_DIR="/home/ga/workspace/data_migration"
RESULT_DIR="/tmp/csv_json_task_results"

# Create results directory
sudo -u ga mkdir -p "$RESULT_DIR"

# Give any running scripts time to complete
sleep 2

# Copy the output JSON file if it exists
if [ -f "$WORKSPACE_DIR/access_control.json" ]; then
    sudo -u ga cp "$WORKSPACE_DIR/access_control.json" "$RESULT_DIR/" 2>/dev/null || true
    echo "✅ Copied access_control.json"
else
    echo "⚠️ Warning: access_control.json not found"
    echo "{}" > "$RESULT_DIR/access_control.json"
fi

# Copy the original CSV for verification reference
if [ -f "$WORKSPACE_DIR/employee_access.csv" ]; then
    sudo -u ga cp "$WORKSPACE_DIR/employee_access.csv" "$RESULT_DIR/" 2>/dev/null || true
    echo "✅ Copied employee_access.csv for verification"
fi

# Copy any transformation scripts they created
echo "Looking for transformation scripts..."
find "$WORKSPACE_DIR" -maxdepth 2 -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.sh" \) \
    -not -name "README.md" \
    -exec sudo -u ga cp {} "$RESULT_DIR/" \; 2>/dev/null || true

# List what was exported
echo ""
echo "📦 Exported files:"
ls -lh "$RESULT_DIR/" 2>/dev/null || echo "No files exported"

echo ""
echo "✅ Export complete"
echo "Results location: $RESULT_DIR"