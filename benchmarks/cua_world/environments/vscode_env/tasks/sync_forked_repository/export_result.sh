#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Sync Forked Repository Result ==="

REPO_DIR="/home/ga/workspace/fastcache"

if [ -d "$REPO_DIR/.git" ]; then
    cd "$REPO_DIR"
    
    echo "Exporting git remotes..."
    sudo -u ga git remote -v > /tmp/git_remotes_list.txt 2>&1 || echo "Failed to get remotes" > /tmp/git_remotes_list.txt
    
    echo "Exporting branch information..."
    sudo -u ga git branch -a > /tmp/git_branches.txt 2>&1 || echo "Failed to get branches" > /tmp/git_branches.txt
    
    echo "Exporting commit log..."
    sudo -u ga git log --all --oneline --graph --decorate -30 > /tmp/git_log_graph.txt 2>&1 || echo "Failed to get log" > /tmp/git_log_graph.txt
    
    echo "Exporting current branch..."
    sudo -u ga git branch --show-current > /tmp/git_current_branch.txt 2>&1 || echo "unknown" > /tmp/git_current_branch.txt
    
    echo "Exporting main branch commit..."
    sudo -u ga git rev-parse main > /tmp/git_main_commit.txt 2>&1 || echo "Failed" > /tmp/git_main_commit.txt
    
    echo "Exporting upstream/main commit (if exists)..."
    sudo -u ga git rev-parse upstream/main > /tmp/git_upstream_main_commit.txt 2>&1 || echo "Not fetched" > /tmp/git_upstream_main_commit.txt
    
    echo "Exporting feature branch commit..."
    sudo -u ga git rev-parse feature/cache-invalidation > /tmp/git_feature_commit.txt 2>&1 || echo "Failed" > /tmp/git_feature_commit.txt
    
    echo "Exporting merge-base (feature vs main)..."
    sudo -u ga git merge-base feature/cache-invalidation main > /tmp/git_merge_base.txt 2>&1 || echo "Failed" > /tmp/git_merge_base.txt
    
    echo "Exporting commit count (main..feature)..."
    sudo -u ga git rev-list --count main..feature/cache-invalidation > /tmp/git_feature_ahead.txt 2>&1 || echo "0" > /tmp/git_feature_ahead.txt
    
    echo "Exporting detailed commit log..."
    sudo -u ga git log --all --format="%H|%s|%an|%ad" -30 > /tmp/git_commit_details.txt 2>&1 || echo "" > /tmp/git_commit_details.txt
    
    echo "✅ Git data exported to /tmp"
else
    echo "⚠️ Git repository not found at $REPO_DIR"
    echo "No repository" > /tmp/git_remotes_list.txt
    echo "No repository" > /tmp/git_branches.txt
fi

echo "✅ Export complete"