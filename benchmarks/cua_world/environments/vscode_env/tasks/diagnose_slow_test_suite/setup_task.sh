#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Diagnose Slow Test Suite Task ==="

WORKSPACE_DIR="/home/ga/workspace/api-testing-project"
TASK_ASSETS="/workspace/tasks/diagnose_slow_test_suite/assets"

# Create project structure
sudo -u ga mkdir -p "$WORKSPACE_DIR"/{src/api,tests,.vscode}

# Copy all asset files
if [ -d "$TASK_ASSETS" ]; then
    echo "Copying project files from assets..."
    sudo -u ga cp -r "$TASK_ASSETS"/* "$WORKSPACE_DIR/"
else
    echo "Warning: Assets directory not found, creating minimal structure"
fi

cd "$WORKSPACE_DIR"
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Create Python virtual environment
echo "Setting up Python virtual environment..."
sudo -u ga python3 -m venv "$WORKSPACE_DIR/venv"

# Install dependencies
echo "Installing dependencies..."
sudo -u ga bash -c "source '$WORKSPACE_DIR/venv/bin/activate' && pip install --quiet pytest pytest-timeout fastapi sqlalchemy requests 2>&1 | tail -5"

# Create pytest configuration
cat > "$WORKSPACE_DIR/pytest.ini" << 'EOF'
[pytest]
testpaths = tests
python_files = test_*.py
python_functions = test_*
addopts = --tb=short -v
EOF

sudo chown ga:ga "$WORKSPACE_DIR/pytest.ini"

# Initialize Git repository
echo "Initializing Git repository..."
cd "$WORKSPACE_DIR"
sudo -u ga git init
sudo -u ga git config user.email "dev@example.com"
sudo -u ga git config user.name "Developer"
sudo -u ga git add .
sudo -u ga git commit -m "Initial project state with slow tests" 2>&1 | tail -3

# Create VSCode tasks configuration
cat > "$WORKSPACE_DIR/.vscode/tasks.json" << 'EOF'
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Run Tests with Profiling",
      "type": "shell",
      "command": "source venv/bin/activate && pytest --durations=20",
      "group": {
        "kind": "test",
        "isDefault": true
      },
      "presentation": {
        "reveal": "always",
        "panel": "new"
      }
    },
    {
      "label": "Run All Tests (Show All Durations)",
      "type": "shell",
      "command": "source venv/bin/activate && pytest --durations=0",
      "group": "test",
      "presentation": {
        "reveal": "always",
        "panel": "new"
      }
    }
  ]
}
EOF

sudo chown ga:ga "$WORKSPACE_DIR/.vscode/tasks.json"

# Create task instructions file
cat > "$WORKSPACE_DIR/TASK_INSTRUCTIONS.md" << 'EOF'
# Test Suite Performance Diagnosis Task

## Context
The test suite has degraded from ~45 seconds to 6+ minutes over 2 months.
Your task is to identify which tests are slow and why.

## Your Goal
Create a report file **`TEST_PERFORMANCE_ANALYSIS.md`** in this directory that includes:

### 1. Top 5 Slowest Individual Tests
For each test, document:
- Test name (e.g., `test_auth.py::test_token_expiry`)
- Execution time (in seconds)
- File location

Example format: