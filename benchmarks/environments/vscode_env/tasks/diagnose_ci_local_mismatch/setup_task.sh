#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Diagnose CI/Local Mismatch Task ==="

WORKSPACE_DIR="/home/ga/workspace/timestamp_service"

# Clean up any existing workspace
sudo rm -rf "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create project structure
sudo -u ga mkdir -p "$WORKSPACE_DIR/.github/workflows"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

# Create CI workflow file
cat > "$WORKSPACE_DIR/.github/workflows/ci.yml" << 'EOF'
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-22.04
    env:
      TZ: UTC
      PYTHONHASHSEED: 0
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      - run: pip install -r requirements.txt
      - run: pytest tests/
EOF

# Create Python source file with the bug
cat > "$WORKSPACE_DIR/src/converter.py" << 'EOF'
import time
from datetime import datetime

def timestamp_to_utc(timestamp: int) -> str:
    """Convert Unix timestamp to UTC string"""
    # BUG: fromtimestamp uses LOCAL timezone, not UTC!
    return datetime.fromtimestamp(timestamp).strftime('%Y-%m-%d %H:%M:%S')

def get_current_timestamp() -> int:
    """Get current Unix timestamp"""
    return int(time.time())
EOF

# Create __init__.py for src module
touch "$WORKSPACE_DIR/src/__init__.py"

# Create test file
cat > "$WORKSPACE_DIR/tests/test_timestamp_conversion.py" << 'EOF'
import pytest
import sys
import os

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from src.converter import timestamp_to_utc

def test_utc_conversion():
    """Test timestamp conversion to UTC string"""
    # 2020-01-01 00:00:00 UTC
    timestamp = 1577836800
    result = timestamp_to_utc(timestamp)
    
    # This expects UTC output
    expected = "2020-01-01 00:00:00"
    assert result == expected, f"Expected {expected}, got {result}"

def test_another_timestamp():
    """Additional test that also depends on timezone"""
    # 2021-06-15 12:00:00 UTC
    timestamp = 1623758400
    result = timestamp_to_utc(timestamp)
    assert result == "2021-06-15 12:00:00"
EOF

# Create __init__.py for tests
touch "$WORKSPACE_DIR/tests/__init__.py"

# Create requirements.txt
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
pytest==7.4.3
EOF

# Create pytest.ini
cat > "$WORKSPACE_DIR/pytest.ini" << 'EOF'
[pytest]
testpaths = tests
python_files = test_*.py
python_functions = test_*
EOF

# Create README
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Timestamp Service

A simple utility for converting Unix timestamps to human-readable UTC strings.

## Running Tests
