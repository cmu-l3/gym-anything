#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Self Review Before PR Result ==="

WORKSPACE_DIR="/home/ga/workspace/auth_feature"
RESULTS_DIR="/tmp/self_review_results"

# Create results directory
mkdir -p "$RESULTS_DIR"

# Give any file operations time to complete
sleep 2

# Export git status
echo "Exporting git status..."
cd "$WORKSPACE_DIR"
sudo -u ga git status --porcelain > "$RESULTS_DIR/git_status.txt" 2>&1 || echo "" > "$RESULTS_DIR/git_status.txt"

# Export staged diff
echo "Exporting staged diff..."
sudo -u ga git diff --cached > "$RESULTS_DIR/staged_diff.txt" 2>&1 || echo "" > "$RESULTS_DIR/staged_diff.txt"

# Export unstaged diff
echo "Exporting unstaged diff..."
sudo -u ga git diff > "$RESULTS_DIR/unstaged_diff.txt" 2>&1 || echo "" > "$RESULTS_DIR/unstaged_diff.txt"

# Copy modified files for verification
echo "Copying files for verification..."
mkdir -p "$RESULTS_DIR/files"

# Copy Python files
cp "$WORKSPACE_DIR/auth/login.py" "$RESULTS_DIR/files/login.py" 2>/dev/null || echo "# File not found" > "$RESULTS_DIR/files/login.py"
cp "$WORKSPACE_DIR/auth/user.py" "$RESULTS_DIR/files/user.py" 2>/dev/null || echo "# File not found" > "$RESULTS_DIR/files/user.py"
cp "$WORKSPACE_DIR/utils/helpers.py" "$RESULTS_DIR/files/helpers.py" 2>/dev/null || echo "# File not found" > "$RESULTS_DIR/files/helpers.py"
cp "$WORKSPACE_DIR/tests/test_auth.py" "$RESULTS_DIR/files/test_auth.py" 2>/dev/null || echo "# File not found" > "$RESULTS_DIR/files/test_auth.py"

# Check if debug test file exists (it should be deleted or unstaged)
if [ -f "$WORKSPACE_DIR/tests/test_debug.py" ]; then
    cp "$WORKSPACE_DIR/tests/test_debug.py" "$RESULTS_DIR/files/test_debug.py" 2>/dev/null
    echo "exists" > "$RESULTS_DIR/test_debug_exists.txt"
else
    echo "deleted" > "$RESULTS_DIR/test_debug_exists.txt"
fi

# List all files in workspace
ls -la "$WORKSPACE_DIR"/ > "$RESULTS_DIR/workspace_listing.txt" 2>&1
ls -la "$WORKSPACE_DIR/auth/" > "$RESULTS_DIR/auth_listing.txt" 2>&1
ls -la "$WORKSPACE_DIR/utils/" > "$RESULTS_DIR/utils_listing.txt" 2>&1
ls -la "$WORKSPACE_DIR/tests/" > "$RESULTS_DIR/tests_listing.txt" 2>&1

# Export git log
sudo -u ga git log --all --format="%H|%s|%an|%ad" > "$RESULTS_DIR/git_log.txt" 2>&1 || echo "" > "$RESULTS_DIR/git_log.txt"

echo "✅ Export complete"
echo "Results directory: $RESULTS_DIR"
echo ""
echo "Git status:"
cat "$RESULTS_DIR/git_status.txt"