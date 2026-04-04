#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Write Bug Reproduction Test Task ==="

WORKSPACE_DIR="/home/ga/workspace/data-processor"
sudo -u ga mkdir -p "$WORKSPACE_DIR"/{src,tests}

# Create buggy source file
cat > "$WORKSPACE_DIR/src/text_utils.py" << 'EOF'
"""Text processing utilities for data pipeline"""
import re

def normalize_whitespace(text, collapse=True):
    """
    Normalize whitespace in text.
    
    Args:
        text: Input string to process
        collapse: If True, collapse multiple spaces into one
    
    Returns:
        Normalized string with cleaned whitespace
    """
    # Strip leading/trailing whitespace
    result = text.strip()
    
    if collapse:
        # Replace multiple whitespace with single space
        result = re.sub(r'\s+', ' ', result)
    
    # BUG: Doesn't handle the case where text.strip() returns ''
    # This causes issues downstream when result[0] is accessed
    first_char = result[0]  # <-- This line crashes on empty strings!
    
    # Ensure first character isn't whitespace (defensive check)
    assert not first_char.isspace(), "First character should not be whitespace"
    
    return result

def sanitize_filename(name):
    """Remove invalid characters from filename"""
    return re.sub(r'[<>:"/\\|?*]', '', name)
EOF

# Create incomplete test file
cat > "$WORKSPACE_DIR/tests/test_text_utils.py" << 'EOF'
"""Tests for text_utils module"""
import pytest
from src.text_utils import normalize_whitespace, sanitize_filename

def test_normalize_basic():
    """Test basic whitespace normalization"""
    assert normalize_whitespace("hello  world") == "hello world"

def test_normalize_leading_trailing():
    """Test stripping leading/trailing whitespace"""
    assert normalize_whitespace("  hello  ") == "hello"

def test_normalize_no_collapse():
    """Test preserving multiple spaces when collapse=False"""
    result = normalize_whitespace("hello    world", collapse=False)
    assert result == "hello    world"

# TODO: Add test for empty string edge case (Bug #4729)
EOF

# Create __init__.py files
touch "$WORKSPACE_DIR/src/__init__.py"
touch "$WORKSPACE_DIR/tests/__init__.py"

# Create pytest.ini
cat > "$WORKSPACE_DIR/pytest.ini" << 'EOF'
[pytest]
testpaths = tests
python_files = test_*.py
python_functions = test_*
EOF

# Create simple README
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Data Processor

Text processing utilities for data pipeline.

## Bug Reports

**Bug #4729**: normalize_whitespace crashes on empty strings
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Ensure pytest is installed
su - ga -c "pip3 install --user pytest" 2>&1 | grep -v "Requirement already satisfied" || true

# Open VSCode with workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open the test file
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/tests/test_text_utils.py'" || true
sleep 1

echo "=== Write Bug Reproduction Test Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Bug Report #4729: normalize_whitespace crashes on empty inputs"
echo "  1. Review src/text_utils.py to understand the bug"
echo "  2. Add test function in tests/test_text_utils.py"
echo "  3. Test should call normalize_whitespace('') or normalize_whitespace('   ')"
echo "  4. Add docstring mentioning Bug #4729"
echo "  5. Save file (Ctrl+S)"
echo "  6. Run: pytest tests/test_text_utils.py::test_normalize_empty_string_bug -v"