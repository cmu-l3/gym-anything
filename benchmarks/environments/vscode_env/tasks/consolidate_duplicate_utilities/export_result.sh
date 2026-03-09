#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Consolidate Duplicate Utilities Result ==="

WORKSPACE_DIR="/home/ga/workspace/email_validator_app"
EXPORT_DIR="/tmp/consolidate_results"

# Ensure VSCode has saved
focus_vscode_window
{
safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to send save command; continuing"
}

sleep 2

# Create export directory
sudo -u ga mkdir -p "$EXPORT_DIR"

cd "$WORKSPACE_DIR"

# Export all relevant files
echo "Exporting source files..."

if [ -f "src/utils/emailValidator.js" ]; then
    sudo -u ga cp "src/utils/emailValidator.js" "$EXPORT_DIR/" 2>/dev/null || true
    echo "✅ Copied emailValidator.js"
else
    echo "⚠️ emailValidator.js not found"
fi

sudo -u ga cp "src/components/RegistrationForm.js" "$EXPORT_DIR/" 2>/dev/null || true
sudo -u ga cp "src/components/LoginForm.js" "$EXPORT_DIR/" 2>/dev/null || true
sudo -u ga cp "src/services/UserService.js" "$EXPORT_DIR/" 2>/dev/null || true
sudo -u ga cp "src/services/NewsletterService.js" "$EXPORT_DIR/" 2>/dev/null || true

echo "✅ Copied component and service files"

# Export git log
echo "Exporting git history..."
sudo -u ga git log --all --format="%H|%s|%an|%ad" > "$EXPORT_DIR/git_log.txt" 2>&1 || echo "No commits" > "$EXPORT_DIR/git_log.txt"

# Export last commit details
sudo -u ga git show HEAD --stat > "$EXPORT_DIR/last_commit.txt" 2>&1 || echo "No commit" > "$EXPORT_DIR/last_commit.txt"

# Export git status
sudo -u ga git status --porcelain > "$EXPORT_DIR/git_status.txt" 2>&1 || echo "" > "$EXPORT_DIR/git_status.txt"

# Set permissions
sudo chmod -R 755 "$EXPORT_DIR"

echo "✅ Export complete"
echo "Results directory: $EXPORT_DIR"
ls -la "$EXPORT_DIR"