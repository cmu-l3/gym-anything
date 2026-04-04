#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Team Snippets Task ==="

WORKSPACE_DIR="/home/ga/workspace/api_service"
SNIPPET_DIR="/home/ga/.config/Code/User/snippets"
TASK_README="/workspace/tasks/create_team_snippets/README.md"

# Create workspace directory
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Ensure snippet directory exists (but don't create python.json - that's the task!)
sudo -u ga mkdir -p "$SNIPPET_DIR"

# Remove any existing python.json to ensure clean state
sudo -u ga rm -f "$SNIPPET_DIR/python.json"

# Create sample Python file for testing snippets
cat > "$WORKSPACE_DIR/endpoints.py" << 'EOF'
"""
API endpoints for user service
TODO: Add proper logging and error handling using team snippets
"""

def get_user(user_id):
    # TODO: Add structured logging here using 'apilog' snippet
    # TODO: Add error handling using 'tryexcept' snippet
    return {"id": user_id, "name": "placeholder"}


def create_user(user_data):
    # TODO: Add logging and error handling
    pass


def update_user(user_id, data):
    # Need logging before operation
    # Need try-except wrapper
    pass
EOF

# Create comprehensive instructions README
cat > "$WORKSPACE_DIR/INSTRUCTIONS.md" << 'EOF'
# Team Snippet Creation Task

## Your Mission
You're a senior developer who is tired of junior team members asking:
- "How do I set up logging properly?"
- "What's our standard error handling pattern?"

**Solution**: Create reusable VSCode snippets so everyone types `apilog` + Tab or `tryexcept` + Tab and gets the correct pattern automatically!

---

## Task Requirements

Create a file: **`~/.config/Code/User/snippets/python.json`**

This file must contain TWO snippets:

### 1. Snippet: API Logging (`apilog`)

**What it should expand to:**