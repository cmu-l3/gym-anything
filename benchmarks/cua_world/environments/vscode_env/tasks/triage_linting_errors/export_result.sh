#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Triage Linting Errors Result ==="

WORKSPACE_DIR="/home/ga/workspace/customer_portal"

# Focus VSCode and save all files
echo "Saving all files..."
focus_vscode_window
sleep 1
{
    safe_xdotool ga :1 key --delay 200 ctrl+k s
    sleep 2
} || {
    echo "⚠️ Failed to send save-all command"
}

# Wait for files to be saved
sleep 2

# Export all Python files to /tmp for verification
echo "Exporting modified Python files..."
mkdir -p /tmp/customer_portal_export/src
mkdir -p /tmp/customer_portal_export/tests

# Copy all Python files
if [ -d "$WORKSPACE_DIR/src" ]; then
    cp -r "$WORKSPACE_DIR/src"/*.py /tmp/customer_portal_export/src/ 2>/dev/null || true
fi

if [ -d "$WORKSPACE_DIR/tests" ]; then
    cp -r "$WORKSPACE_DIR/tests"/*.py /tmp/customer_portal_export/tests/ 2>/dev/null || true
fi

# Run linters and capture output
echo "Running linters for verification..."
cd "$WORKSPACE_DIR"

# Run pylint and capture output
echo "Running pylint..."
pylint src/ tests/ --output-format=text > /tmp/pylint_output.txt 2>&1 || true

# Run mypy and capture output
echo "Running mypy..."
mypy src/ tests/ > /tmp/mypy_output.txt 2>&1 || true

# Count errors in pylint output
echo "Counting pylint errors..."
grep -c "error" /tmp/pylint_output.txt > /tmp/pylint_error_count.txt 2>/dev/null || echo "0" > /tmp/pylint_error_count.txt

# Count errors in mypy output
echo "Counting mypy errors..."
grep -c "error:" /tmp/mypy_output.txt > /tmp/mypy_error_count.txt 2>/dev/null || echo "0" > /tmp/mypy_error_count.txt

# Create a summary file
cat > /tmp/linting_summary.txt << EOF
Pylint errors: $(cat /tmp/pylint_error_count.txt)
Mypy errors: $(cat /tmp/mypy_error_count.txt)
Files exported to: /tmp/customer_portal_export/
EOF

echo "✅ Export complete"
echo "Exported files:"
ls -la /tmp/customer_portal_export/src/ 2>/dev/null || echo "  (no src files)"
ls -la /tmp/customer_portal_export/tests/ 2>/dev/null || echo "  (no test files)"
cat /tmp/linting_summary.txt