#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Review Uncommitted Diff Result ==="

REPO_DIR="/home/ga/workspace/api_service"
SUMMARY_PATH="/home/ga/workspace/REVIEW_SUMMARY.md"

# Focus VSCode and save all files
focus_vscode_window
sleep 1

# Save all open files
echo "Saving all files..."
su - ga -c "DISPLAY=:1 xdotool key --delay 100 ctrl+k s" || true
sleep 2

# Alternative: Ctrl+S
su - ga -c "DISPLAY=:1 xdotool key --delay 100 ctrl+s" || true
sleep 1

# Wait for files to be written
wait_for_file "$REPO_DIR/api/routes/orders.py" 5
wait_for_file "$REPO_DIR/api/services/payment.py" 5

# Export git status
if [ -d "$REPO_DIR/.git" ]; then
    echo "Exporting git status..."
    cd "$REPO_DIR"
    sudo -u ga git status --porcelain > /tmp/git_status.txt 2>&1 || echo "" > /tmp/git_status.txt
    
    echo "Exporting git diff stats..."
    sudo -u ga git diff --stat > /tmp/git_diff_stat.txt 2>&1 || echo "" > /tmp/git_diff_stat.txt
fi

# Copy modified files to /tmp for verification
echo "Copying files for verification..."
sudo -u ga cp "$REPO_DIR/api/routes/orders.py" /tmp/orders.py 2>/dev/null || echo "orders.py not found" > /tmp/orders.py
sudo -u ga cp "$REPO_DIR/api/services/payment.py" /tmp/payment.py 2>/dev/null || echo "payment.py not found" > /tmp/payment.py
sudo -u ga cp "$REPO_DIR/api/utils/logger.py" /tmp/logger.py 2>/dev/null || echo "logger.py not found" > /tmp/logger.py
sudo -u ga cp "$REPO_DIR/tests/test_orders.py" /tmp/test_orders.py 2>/dev/null || echo "test_orders.py not found" > /tmp/test_orders.py

# Copy review summary if it exists
if [ -f "$SUMMARY_PATH" ]; then
    echo "Copying review summary..."
    sudo -u ga cp "$SUMMARY_PATH" /tmp/REVIEW_SUMMARY.md
else
    echo "Review summary not found" > /tmp/REVIEW_SUMMARY.md
fi

# Export file modification times for workflow verification
echo "Exporting file timestamps..."
stat -c "%Y %n" "$REPO_DIR/api/routes/orders.py" 2>/dev/null > /tmp/file_timestamps.txt || echo "0 orders.py" > /tmp/file_timestamps.txt
stat -c "%Y %n" "$REPO_DIR/api/services/payment.py" 2>/dev/null >> /tmp/file_timestamps.txt || echo "0 payment.py" >> /tmp/file_timestamps.txt
stat -c "%Y %n" "$REPO_DIR/api/utils/logger.py" 2>/dev/null >> /tmp/file_timestamps.txt || echo "0 logger.py" >> /tmp/file_timestamps.txt
stat -c "%Y %n" "$REPO_DIR/tests/test_orders.py" 2>/dev/null >> /tmp/file_timestamps.txt || echo "0 test_orders.py" >> /tmp/file_timestamps.txt
stat -c "%Y %n" "$SUMMARY_PATH" 2>/dev/null >> /tmp/file_timestamps.txt || echo "0 REVIEW_SUMMARY.md" >> /tmp/file_timestamps.txt

echo "✅ Export complete"
echo "Repository: $REPO_DIR"
echo "Summary: $SUMMARY_PATH"