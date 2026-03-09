#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Run Failing Tests Result ==="

WORKSPACE="/home/ga/workspace/pytest_project"

# Give any running tests time to complete
sleep 2

# Export pytest cache if it exists (indicates tests were run)
if [ -d "$WORKSPACE/.pytest_cache" ]; then
    echo "✅ Pytest cache found - copying..."
    
    # Copy cache directory structure (contains lastfailed, nodeids, etc.)
    mkdir -p /tmp/pytest_cache_export
    cp -r "$WORKSPACE/.pytest_cache"/* /tmp/pytest_cache_export/ 2>/dev/null || true
    
    # Export lastfailed file specifically (contains failed test info)
    if [ -f "$WORKSPACE/.pytest_cache/v/cache/lastfailed" ]; then
        cp "$WORKSPACE/.pytest_cache/v/cache/lastfailed" /tmp/pytest_lastfailed.json
        echo "✅ Lastfailed info exported"
    else
        echo "{}" > /tmp/pytest_lastfailed.json
        echo "⚠️ No lastfailed file found"
    fi
    
    # Export nodeids (contains discovered tests)
    if [ -f "$WORKSPACE/.pytest_cache/v/cache/nodeids" ]; then
        cp "$WORKSPACE/.pytest_cache/v/cache/nodeids" /tmp/pytest_nodeids.json
        echo "✅ Test nodeids exported"
    fi
else
    echo "⚠️ No pytest cache found"
    echo "{}" > /tmp/pytest_lastfailed.json
    mkdir -p /tmp/pytest_cache_export
fi

# Export VSCode settings to verify pytest configuration
if [ -f "/home/ga/.config/Code/User/settings.json" ]; then
    cp "/home/ga/.config/Code/User/settings.json" /tmp/vscode_settings.json
    echo "✅ VSCode settings exported"
else
    echo "{}" > /tmp/vscode_settings.json
fi

# Export bash history to check for pytest commands
if [ -f "/home/ga/.bash_history" ]; then
    cp "/home/ga/.bash_history" /tmp/bash_history.txt
    echo "✅ Bash history exported"
else
    echo "" > /tmp/bash_history.txt
fi

# Export source file checksums to verify they weren't modified
md5sum "$WORKSPACE/src/calculator.py" > /tmp/final_calculator_checksum.txt 2>/dev/null || echo "" > /tmp/final_calculator_checksum.txt
md5sum "$WORKSPACE/tests/test_calculator.py" > /tmp/final_test_checksum.txt 2>/dev/null || echo "" > /tmp/final_test_checksum.txt

# Try to capture any pytest output files
if [ -f "$WORKSPACE/pytest_output.txt" ]; then
    cp "$WORKSPACE/pytest_output.txt" /tmp/pytest_output.txt
fi

# Check if VSCode test results exist in workspace storage
VSCODE_STORAGE="/home/ga/.config/Code/User/workspaceStorage"
if [ -d "$VSCODE_STORAGE" ]; then
    # Find the workspace storage directory for this project
    WORKSPACE_HASH=$(echo -n "$WORKSPACE" | md5sum | cut -d' ' -f1)
    
    # Search for test-related state files
    find "$VSCODE_STORAGE" -name "*test*" -o -name "*pytest*" 2>/dev/null | head -5 > /tmp/vscode_test_files.txt || echo "" > /tmp/vscode_test_files.txt
fi

# Export task completion time
date +%s > /tmp/task_end_time.txt

echo "=== Export Complete ==="
echo "Exported files:"
echo "  - /tmp/pytest_lastfailed.json (failed tests info)"
echo "  - /tmp/pytest_cache_export/ (pytest cache)"
echo "  - /tmp/vscode_settings.json (VSCode config)"
echo "  - /tmp/bash_history.txt (command history)"
echo "  - /tmp/*_checksum.txt (file integrity)"