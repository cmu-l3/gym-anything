#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Run Failing Tests Task ==="

WORKSPACE="/home/ga/workspace/pytest_project"
SRC_DIR="$WORKSPACE/src"
TEST_DIR="$WORKSPACE/tests"

# Create project structure
sudo -u ga mkdir -p "$SRC_DIR"
sudo -u ga mkdir -p "$TEST_DIR"

# Create calculator.py with intentional bugs
cat > "$SRC_DIR/calculator.py" << 'EOF'
"""Simple calculator with arithmetic operations"""

def add(a, b):
    """Add two numbers"""
    return a + b

def subtract(a, b):
    """Subtract b from a"""
    return a + b  # BUG: Should be a - b

def multiply(a, b):
    """Multiply two numbers"""
    return a * b

def divide(a, b):
    """Divide a by b"""
    if b == 0:
        raise ValueError("Cannot divide by zero")
    return a  # BUG: Should be a / b

def power(a, b):
    """Raise a to power b"""
    return a ** b
EOF

# Create test file
cat > "$TEST_DIR/test_calculator.py" << 'EOF'
"""Unit tests for calculator module"""
import pytest
import sys
sys.path.insert(0, '/home/ga/workspace/pytest_project/src')

from calculator import add, subtract, multiply, divide, power

def test_add():
    """Test addition"""
    assert add(2, 3) == 5
    assert add(-1, 1) == 0
    assert add(0, 0) == 0

def test_subtract():
    """Test subtraction"""
    assert subtract(5, 3) == 2  # Will FAIL (returns 8)
    assert subtract(0, 5) == -5  # Will FAIL (returns 5)

def test_multiply():
    """Test multiplication"""
    assert multiply(3, 4) == 12
    assert multiply(-2, 3) == -6
    assert multiply(0, 5) == 0

def test_divide():
    """Test division"""
    assert divide(10, 2) == 5.0  # Will FAIL (returns 10)
    assert divide(7, 2) == 3.5   # Will FAIL (returns 7)
    
    with pytest.raises(ValueError):
        divide(5, 0)

def test_power():
    """Test exponentiation"""
    assert power(2, 3) == 8
    assert power(5, 2) == 25
    assert power(2, 0) == 1
EOF

# Create __init__.py files
touch "$SRC_DIR/__init__.py"
touch "$TEST_DIR/__init__.py"

sudo chown -R ga:ga "$WORKSPACE"

# Ensure pytest is installed
echo "Installing pytest..."
sudo -u ga pip3 install pytest pytest-json-report --quiet 2>&1 || echo "⚠️ pytest installation had warnings (may already be installed)"

# Configure VSCode for pytest
mkdir -p "/home/ga/.config/Code/User"
cat > "/home/ga/.config/Code/User/settings.json" << 'EOF'
{
  "telemetry.telemetryLevel": "off",
  "update.mode": "none",
  "extensions.autoUpdate": false,
  "files.autoSave": "afterDelay",
  "files.autoSaveDelay": 1000,
  "python.testing.pytestEnabled": true,
  "python.testing.unittestEnabled": false,
  "python.testing.pytestArgs": [
    "tests"
  ],
  "python.testing.autoTestDiscoverOnSaveEnabled": true,
  "editor.fontSize": 14,
  "workbench.startupEditor": "none"
}
EOF

# Clear any existing pytest cache
rm -rf "$WORKSPACE/.pytest_cache" 2>/dev/null || true

# Store initial file checksums for verification
md5sum "$SRC_DIR/calculator.py" > /tmp/initial_calculator_checksum.txt 2>/dev/null || true
md5sum "$TEST_DIR/test_calculator.py" > /tmp/initial_test_checksum.txt 2>/dev/null || true

# Save task start time for verification
date +%s > /tmp/task_start_time.txt

# Open VSCode with the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Give VSCode time to discover tests
sleep 3

echo "=== Run Failing Tests Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Workspace: $WORKSPACE"
echo "  Project contains:"
echo "    - src/calculator.py (with 2 intentional bugs)"
echo "    - tests/test_calculator.py (5 unit tests)"
echo ""
echo "  Your task:"
echo "    1. Open Testing panel (flask icon on left sidebar)"
echo "    2. Wait for test discovery"
echo "    3. Identify failing tests (red X icons)"
echo "    4. Run at least one failing test individually"
echo "    5. Review the test output"
echo ""
echo "  Expected results: 2 failed, 3 passed"
echo "  DO NOT modify the source code!"