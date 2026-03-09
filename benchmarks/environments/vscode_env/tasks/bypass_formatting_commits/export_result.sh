#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Bypass Formatting Commits Result ==="

WORKSPACE="/home/ga/workspace/ecommerce-site"

# Export git log
if [ -d "$WORKSPACE/.git" ]; then
    echo "Exporting git log..."
    cd "$WORKSPACE"
    sudo -u ga git log --all --format="%H|%s|%an|%ad" > /tmp/git_log_bypass.txt 2>&1 || echo "No commits" > /tmp/git_log_bypass.txt
    
    echo "Exporting git config..."
    sudo -u ga git config --get blame.ignoreRevsFile > /tmp/git_blame_config.txt 2>&1 || echo "" > /tmp/git_blame_config.txt
    
    # Copy .git-blame-ignore-revs if it exists
    if [ -f "$WORKSPACE/.git-blame-ignore-revs" ]; then
        cp "$WORKSPACE/.git-blame-ignore-revs" /tmp/git-blame-ignore-revs.txt
        echo "✅ .git-blame-ignore-revs file exported"
    else
        echo "" > /tmp/git-blame-ignore-revs.txt
        echo "⚠️ .git-blame-ignore-revs file not found"
    fi
    
    # Copy any investigation report files
    for report in "$WORKSPACE"/INVESTIGATION_REPORT.* "$WORKSPACE"/investigation_report.* "$WORKSPACE"/FINDINGS.* "$WORKSPACE"/bug_investigation.*; do
        if [ -f "$report" ]; then
            cp "$report" "/tmp/$(basename "$report")"
            echo "✅ Report file exported: $(basename "$report")"
        fi
    done
    
    # Also check for .txt files that might be reports
    if [ -f "$WORKSPACE/INVESTIGATION_REPORT.txt" ]; then
        cp "$WORKSPACE/INVESTIGATION_REPORT.txt" /tmp/
    fi
else
    echo "⚠️ Git repository not found"
    echo "No git repository" > /tmp/git_log_bypass.txt
    echo "" > /tmp/git_blame_config.txt
    echo "" > /tmp/git-blame-ignore-revs.txt
fi

echo "✅ Export complete"
echo "Exported files to /tmp:"
ls -la /tmp/git*.txt /tmp/INVESTIGATION*.* /tmp/investigation*.* /tmp/FINDINGS*.* /tmp/bug_investigation*.* 2>/dev/null || true