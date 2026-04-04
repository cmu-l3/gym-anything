#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Modernize Tutorial Code Result ==="

WORKSPACE_DIR="/home/ga/workspace/api_client"

# Focus VSCode and save all files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to save files via xdotool; continuing"
}

# Wait for file to be written
sleep 2

# Export the decorators.py file for verification
echo "Exporting decorators.py..."
if [ -f "$WORKSPACE_DIR/utils/decorators.py" ]; then
    cp "$WORKSPACE_DIR/utils/decorators.py" /tmp/decorators_result.py 2>&1 || true
    echo "✅ decorators.py exported to /tmp"
else
    echo "⚠️ decorators.py not found"
    touch /tmp/decorators_result.py
fi

# Run tests and capture output
echo "Running tests..."
cd "$WORKSPACE_DIR"
sudo -u ga python3 -m pytest tests/test_rate_limiter.py -v --tb=short > /tmp/pytest_output.txt 2>&1 || true
echo "✅ Test results exported to /tmp"

# Run pylint and capture output
echo "Running pylint..."
sudo -u ga python3 -m pylint utils/decorators.py --rcfile=.pylintrc > /tmp/pylint_output.txt 2>&1 || true
echo "✅ Pylint results exported to /tmp"

# Run black check
echo "Checking black formatting..."
sudo -u ga python3 -m black --check utils/decorators.py > /tmp/black_output.txt 2>&1
BLACK_EXIT_CODE=$?
echo $BLACK_EXIT_CODE > /tmp/black_exit_code.txt
echo "✅ Black check results exported to /tmp"

# Export file metadata
echo "Exporting metadata..."
stat "$WORKSPACE_DIR/utils/decorators.py" > /tmp/decorators_stat.txt 2>&1 || echo "File not found" > /tmp/decorators_stat.txt

echo "✅ Export complete"
echo "Results location: /tmp/decorators_result.py"
echo "Tests output: /tmp/pytest_output.txt"
echo "Pylint output: /tmp/pylint_output.txt"
echo "Black output: /tmp/black_output.txt"