#!/bin/bash
# set -euo pipefail

echo "=== Exporting Fix Git Identity Leak Result ==="

PERSONAL_REPO="/home/ga/workspace/personal/oss-library"

# Export git commit info from personal repo
if [ -d "$PERSONAL_REPO/.git" ]; then
    echo "Exporting commit information..."
    cd "$PERSONAL_REPO"
    sudo -u ga git log -1 --format="%H|%an|%ae|%s" > /tmp/personal_commit.txt 2>&1 || echo "No commits" > /tmp/personal_commit.txt
    
    # Also export last 3 commits for verification
    sudo -u ga git log -3 --format="%H|%an|%ae|%s" > /tmp/personal_commits_all.txt 2>&1 || echo "No commits" > /tmp/personal_commits_all.txt
else
    echo "No git repository" > /tmp/personal_commit.txt
    echo "No git repository" > /tmp/personal_commits_all.txt
fi

# Export git configuration files
echo "Exporting git configuration files..."
cp /home/ga/.gitconfig /tmp/gitconfig.txt 2>/dev/null || echo "No .gitconfig" > /tmp/gitconfig.txt
cp /home/ga/.gitconfig-work /tmp/gitconfig-work.txt 2>/dev/null || echo "No .gitconfig-work" > /tmp/gitconfig-work.txt
cp /home/ga/.gitconfig-personal /tmp/gitconfig-personal.txt 2>/dev/null || echo "No .gitconfig-personal" > /tmp/gitconfig-personal.txt

# Test git config resolution in different directories
echo "Testing config resolution..."
cd /home/ga/workspace/work/corporate-api 2>/dev/null && {
    WORK_NAME=$(sudo -u ga git config user.name 2>/dev/null || echo "not-set")
    WORK_EMAIL=$(sudo -u ga git config user.email 2>/dev/null || echo "not-set")
    echo "$WORK_NAME|$WORK_EMAIL" > /tmp/work_config_test.txt
} || {
    echo "not-set|not-set" > /tmp/work_config_test.txt
}

cd /home/ga/workspace/personal/oss-library 2>/dev/null && {
    PERSONAL_NAME=$(sudo -u ga git config user.name 2>/dev/null || echo "not-set")
    PERSONAL_EMAIL=$(sudo -u ga git config user.email 2>/dev/null || echo "not-set")
    echo "$PERSONAL_NAME|$PERSONAL_EMAIL" > /tmp/personal_config_test.txt
} || {
    echo "not-set|not-set" > /tmp/personal_config_test.txt
}

echo "✅ Export complete"
echo "Personal repo commit info exported to /tmp"
cat /tmp/personal_commit.txt