#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Sync Forked Repository Task ==="

WORKSPACE="/home/ga/workspace"
REPO_DIR="$WORKSPACE/fastcache"

# Clean up any existing directories
sudo -u ga rm -rf "$REPO_DIR"
sudo -u ga mkdir -p "$WORKSPACE"

# Create temporary "remote" repositories (bare repos to simulate GitHub)
sudo -u ga mkdir -p /tmp/git_remotes
sudo -u ga rm -rf /tmp/git_remotes/fastcache-fork.git
sudo -u ga rm -rf /tmp/git_remotes/fastcache-upstream.git

echo "Creating bare repositories for fork and upstream..."
cd /tmp/git_remotes
sudo -u ga git init --bare fastcache-fork.git
sudo -u ga git init --bare fastcache-upstream.git

# Create initial repository with content
echo "Initializing local repository..."
sudo -u ga mkdir -p "$REPO_DIR/src"
sudo -u ga mkdir -p "$REPO_DIR/tests"
cd "$REPO_DIR"

sudo -u ga git init
sudo -u ga git config user.email "agent@example.com"
sudo -u ga git config user.name "Test Agent"

# Create initial project files
sudo -u ga tee "$REPO_DIR/src/cache.py" > /dev/null << 'EOF'
"""Simple cache implementation"""

class Cache:
    def __init__(self):
        self.store = {}
    
    def get(self, key):
        return self.store.get(key)
    
    def set(self, key, value):
        self.store[key] = value
EOF

sudo -u ga tee "$REPO_DIR/tests/test_cache.py" > /dev/null << 'EOF'
import unittest
from src.cache import Cache

class TestCache(unittest.TestCase):
    def test_basic(self):
        cache = Cache()
        cache.set("key", "value")
        self.assertEqual(cache.get("key"), "value")
EOF

sudo -u ga tee "$REPO_DIR/README.md" > /dev/null << 'EOF'
# FastCache

A simple caching library for Python.

## Features
- Get and set cache values
- Simple dictionary-based storage
EOF

sudo -u ga tee "$REPO_DIR/setup.py" > /dev/null << 'EOF'
from setuptools import setup, find_packages

setup(
    name="fastcache",
    version="0.1.0",
    packages=find_packages(),
    description="A simple caching library",
)
EOF

# Initial commit
echo "Creating initial commit..."
cd "$REPO_DIR"
sudo -u ga git add .
sudo -u ga git commit -m "Initial commit" > /dev/null 2>&1
sudo -u ga git branch -M main

# Push to both "remotes" initially
echo "Setting up origin remote (your fork)..."
sudo -u ga git remote add origin /tmp/git_remotes/fastcache-fork.git
sudo -u ga git push -u origin main > /dev/null 2>&1

# Also push to upstream for setup
sudo -u ga git remote add temp_upstream /tmp/git_remotes/fastcache-upstream.git
sudo -u ga git push temp_upstream main > /dev/null 2>&1

# Now simulate upstream getting ahead with 5 new commits
echo "Creating upstream commits (simulating upstream progress)..."
cd "$REPO_DIR"

for i in {1..5}; do
    echo "## Update $i - Bug fixes and improvements" >> README.md
    sudo -u ga git add README.md
    sudo -u ga git commit -m "Upstream update $i - bug fixes and improvements" > /dev/null 2>&1
done

# Push these to upstream only
sudo -u ga git push temp_upstream main > /dev/null 2>&1

# Reset local main to old state (before the 5 commits)
echo "Resetting local main to simulate outdated fork..."
sudo -u ga git reset --hard HEAD~5 > /dev/null 2>&1

# Remove temp_upstream remote (agent needs to add it back)
sudo -u ga git remote remove temp_upstream

# Create feature branch based on old main
echo "Creating feature branch..."
sudo -u ga git checkout -b feature/cache-invalidation > /dev/null 2>&1

# Add feature commits
sudo -u ga tee -a "$REPO_DIR/src/cache.py" > /dev/null << 'EOF'

    def invalidate(self, key):
        """Invalidate a cache entry"""
        if key in self.store:
            del self.store[key]
            return True
        return False
EOF

sudo -u ga git add src/cache.py
sudo -u ga git commit -m "Add cache invalidation method" > /dev/null 2>&1

sudo -u ga tee -a "$REPO_DIR/tests/test_cache.py" > /dev/null << 'EOF'

    def test_invalidate(self):
        cache = Cache()
        cache.set("key", "value")
        self.assertTrue(cache.invalidate("key"))
        self.assertIsNone(cache.get("key"))
EOF

sudo -u ga git add tests/test_cache.py
sudo -u ga git commit -m "Add tests for cache invalidation" > /dev/null 2>&1

# Ensure we're on feature branch
sudo -u ga git checkout feature/cache-invalidation > /dev/null 2>&1

sudo chown -R ga:ga "$REPO_DIR"

echo "Repository state:"
echo "  Current branch: $(cd $REPO_DIR && sudo -u ga git branch --show-current)"
echo "  Remotes:"
cd "$REPO_DIR" && sudo -u ga git remote -v
echo ""
echo "  Local main is 5 commits behind upstream"
echo "  Feature branch has 2 commits"

# Open VSCode with the repository
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$REPO_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Sync Forked Repository Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Add upstream remote: git remote add upstream /tmp/git_remotes/fastcache-upstream.git"
echo "  2. Fetch upstream: git fetch upstream"
echo "  3. Update main: git checkout main && git merge upstream/main"
echo "  4. Rebase feature: git checkout feature/cache-invalidation && git rebase main"