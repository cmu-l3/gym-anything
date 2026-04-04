#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Code Coverage Visualization Task ==="

WORKSPACE_DIR="/home/ga/workspace/coverage_task"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"
sudo -u ga mkdir -p "$WORKSPACE_DIR/.vscode"

# Create calculator.py with intentional coverage gaps
cat > "$WORKSPACE_DIR/calculator.py" << 'EOF'
"""
Simple calculator module with intentional test coverage gaps.
Only add() and subtract() have tests - the rest are UNTESTED.
"""

def add(a, b):
    """Add two numbers - THIS IS TESTED"""
    return a + b


def subtract(a, b):
    """Subtract two numbers - THIS IS TESTED"""
    return a - b


def multiply(a, b):
    """Multiply two numbers - NOT TESTED (coverage gap!)"""
    return a * b


def divide(a, b):
    """Divide two numbers - NOT TESTED (coverage gap!)"""
    if b == 0:
        raise ValueError("Cannot divide by zero")
    return a / b


def power(a, b):
    """Raise a to power b - NOT TESTED (coverage gap!)"""
    return a ** b
EOF

# Create utils.py with mixed coverage
cat > "$WORKSPACE_DIR/utils.py" << 'EOF'
"""
Utility functions with mixed test coverage.
"""

def format_number(n):
    """Format number - NOT TESTED"""
    return f"{n:,}"


def is_even(n):
    """Check if number is even - THIS IS TESTED"""
    return n % 2 == 0
EOF

# Create test file covering only some functions
cat > "$WORKSPACE_DIR/tests/test_calculator.py" << 'EOF'
"""
Tests for calculator module - intentionally incomplete coverage
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from calculator import add, subtract
from utils import is_even


def test_add():
    """Test add function"""
    assert add(2, 3) == 5
    assert add(-1, 1) == 0
    assert add(0, 0) == 0


def test_subtract():
    """Test subtract function"""
    assert subtract(5, 3) == 2
    assert subtract(0, 5) == -5
    assert subtract(10, 10) == 0


def test_is_even():
    """Test is_even function"""
    assert is_even(2) == True
    assert is_even(3) == False
    assert is_even(0) == True


# NOTE: multiply, divide, power are NOT tested - coverage gaps!
# NOTE: format_number is NOT tested - coverage gap!
EOF

# Create pytest.ini configuration
cat > "$WORKSPACE_DIR/pytest.ini" << 'EOF'
[pytest]
testpaths = tests
python_files = test_*.py
python_functions = test_*
addopts = -v
EOF

# Create __init__.py for tests
touch "$WORKSPACE_DIR/tests/__init__.py"

# Create a README explaining the task
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Coverage Visualization Task

This project has intentional test coverage gaps to practice setting up coverage visualization.

## Current Test Coverage

**Tested functions:**
- `calculator.add()` ✅
- `calculator.subtract()` ✅
- `utils.is_even()` ✅

**Untested functions (coverage gaps):**
- `calculator.multiply()` ❌
- `calculator.divide()` ❌
- `calculator.power()` ❌
- `utils.format_number()` ❌

Expected coverage: ~40-60%

## Task

1. Install a coverage visualization extension (e.g., Coverage Gutters)
2. Generate coverage report: `pytest --cov=. --cov-report=xml`
3. Configure the extension to display coverage
4. Verify coverage indicators appear in editor
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Ensure pytest and pytest-cov are installed
echo "Installing pytest and pytest-cov..."
su - ga -c "pip3 install --user pytest pytest-cov 2>&1 | tail -5" || {
    echo "⚠️ Warning: Failed to install pytest/pytest-cov, may already be installed"
}

# Uninstall any existing coverage extensions to ensure clean state
echo "Removing any pre-existing coverage extensions..."
su - ga -c "DISPLAY=:1 code --uninstall-extension ryanluker.vscode-coverage-gutters 2>&1" || true
su - ga -c "DISPLAY=:1 code --uninstall-extension markis.code-coverage 2>&1" || true
sleep 2

# Delete any pre-existing coverage files
rm -f "$WORKSPACE_DIR/coverage.xml" "$WORKSPACE_DIR/lcov.info" "$WORKSPACE_DIR/.coverage" 2>/dev/null || true

# Open VSCode with workspace
echo "Opening VSCode with workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/calculator.py'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Code Coverage Visualization Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Install coverage extension (Ctrl+Shift+P → Extensions: Install Extensions → search 'coverage gutters')"
echo "  2. Open terminal (Ctrl+\`) and run: pytest --cov=. --cov-report=xml"
echo "  3. Configure extension in settings to use coverage.xml"
echo "  4. Activate coverage display (Command Palette or extension icon)"
echo "  5. Verify coverage indicators appear in calculator.py"
echo ""
echo "📊 Expected coverage: ~40-60% (only 3 of 7 functions are tested)"