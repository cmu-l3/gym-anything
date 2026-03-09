#!/bin/bash
# set -euo pipefail

echo "=== Exporting Pre-Commit Hooks Result ==="

WORKSPACE="/home/ga/workspace/myapp"

# Ensure any open files are saved
if pgrep -f "code" > /dev/null; then
    echo "Attempting to save any open files..."
    su - ga -c "DISPLAY=:1 xdotool key --delay 100 ctrl+s" 2>/dev/null || true
    sleep 1
fi

# Export .pre-commit-config.yaml if it exists
if [ -f "$WORKSPACE/.pre-commit-config.yaml" ]; then
    echo "✓ Found .pre-commit-config.yaml"
    cp "$WORKSPACE/.pre-commit-config.yaml" /tmp/precommit_config.yaml
else
    echo "✗ .pre-commit-config.yaml not found"
    echo "FILE_NOT_FOUND" > /tmp/precommit_config.yaml
fi

# Export requirements files
if [ -f "$WORKSPACE/requirements.txt" ]; then
    cp "$WORKSPACE/requirements.txt" /tmp/requirements.txt
else
    echo "NO_FILE" > /tmp/requirements.txt
fi

if [ -f "$WORKSPACE/requirements-dev.txt" ]; then
    cp "$WORKSPACE/requirements-dev.txt" /tmp/requirements-dev.txt
else
    echo "NO_FILE" > /tmp/requirements-dev.txt
fi

# Check if git hooks are installed
if [ -f "$WORKSPACE/.git/hooks/pre-commit" ]; then
    echo "✓ Git pre-commit hook found"
    echo "INSTALLED" > /tmp/hook_status.txt
    ls -la "$WORKSPACE/.git/hooks/pre-commit" >> /tmp/hook_status.txt
    # Get first few lines of hook file
    head -n 5 "$WORKSPACE/.git/hooks/pre-commit" >> /tmp/hook_status.txt 2>&1 || true
else
    echo "✗ Git pre-commit hook not found"
    echo "NOT_INSTALLED" > /tmp/hook_status.txt
fi

# Export git log
cd "$WORKSPACE"
sudo -u ga git log --all --format="%H|%s|%an|%ad" > /tmp/git_log.txt 2>&1 || echo "No commits" > /tmp/git_log.txt

# Export git status
sudo -u ga git status --porcelain > /tmp/git_status.txt 2>&1 || echo "" > /tmp/git_status.txt

# Check if config was committed (check git log for the file)
sudo -u ga git log --all --oneline -- .pre-commit-config.yaml > /tmp/config_commits.txt 2>&1 || echo "" > /tmp/config_commits.txt

# Export source files to check if they were formatted
if [ -f "$WORKSPACE/src/app.py" ]; then
    cp "$WORKSPACE/src/app.py" /tmp/app_py_final.txt
fi

if [ -f "$WORKSPACE/src/models.py" ]; then
    cp "$WORKSPACE/src/models.py" /tmp/models_py_final.txt
fi

echo "✅ Export complete"
echo "Files exported to /tmp/"
ls -la /tmp/precommit_config.yaml /tmp/hook_status.txt /tmp/git_log.txt 2>/dev/null || true