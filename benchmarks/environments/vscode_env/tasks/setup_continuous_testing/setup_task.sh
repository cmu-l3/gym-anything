#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Continuous Testing Task ==="

WORKSPACE_DIR="/home/ga/workspace/data_processor"
USER_ID="ga"

# Create workspace directory structure
sudo -u $USER_ID mkdir -p "$WORKSPACE_DIR"/{src,tests,.vscode}

echo "Creating Python project files..."

# Create source files
cat > "$WORKSPACE_DIR/src/__init__.py" << 'EOF'
"""Data processor package"""
EOF

cat > "$WORKSPACE_DIR/src/validator.py" << 'EOF'
"""Data validation functions"""

def validate_email(email: str) -> bool:
    """Validate email format."""
    if not email or '@' not in email:
        return False
    local, domain = email.split('@', 1)
    if not local or not domain:
        return False
    if '.' not in domain:
        return False
    return True

def validate_age(age: int) -> bool:
    """Validate age is reasonable."""
    return 0 <= age <= 150

def validate_phone(phone: str) -> bool:
    """Validate phone number format."""
    # Simple validation: remove common separators and check length
    digits = ''.join(c for c in phone if c.isdigit())
    return len(digits) >= 10
EOF

cat > "$WORKSPACE_DIR/src/utils.py" << 'EOF'
"""Utility functions"""

def sanitize_input(text: str) -> str:
    """Remove dangerous characters."""
    return text.strip()

def normalize_whitespace(text: str) -> str:
    """Normalize whitespace in text."""
    return ' '.join(text.split())
EOF

# Create test files
cat > "$WORKSPACE_DIR/tests/__init__.py" << 'EOF'
"""Tests package"""
EOF

cat > "$WORKSPACE_DIR/tests/test_validator.py" << 'EOF'
"""Tests for validator module"""
import pytest
from src.validator import validate_email, validate_age, validate_phone

def test_validate_email_valid():
    assert validate_email("user@example.com") == True
    assert validate_email("test.user@domain.co.uk") == True

def test_validate_email_invalid():
    assert validate_email("invalid-email") == False
    assert validate_email("@example.com") == False
    assert validate_email("user@") == False
    assert validate_email("") == False

def test_validate_age_valid():
    assert validate_age(25) == True
    assert validate_age(0) == True
    assert validate_age(150) == True

def test_validate_age_invalid():
    assert validate_age(-1) == False
    assert validate_age(151) == False

def test_validate_phone():
    assert validate_phone("123-456-7890") == True
    assert validate_phone("1234567890") == True
    assert validate_phone("(123) 456-7890") == True
    assert validate_phone("123") == False
EOF

cat > "$WORKSPACE_DIR/tests/test_utils.py" << 'EOF'
"""Tests for utils module"""
from src.utils import sanitize_input, normalize_whitespace

def test_sanitize_input():
    assert sanitize_input("  hello  ") == "hello"
    assert sanitize_input("test") == "test"
    assert sanitize_input("  ") == ""

def test_normalize_whitespace():
    assert normalize_whitespace("hello  world") == "hello world"
    assert normalize_whitespace("  multiple   spaces  ") == "multiple spaces"
EOF

# Create pytest.ini
cat > "$WORKSPACE_DIR/pytest.ini" << 'EOF'
[pytest]
testpaths = tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*
addopts = -v --tb=short
EOF

# Create requirements.txt
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
pytest>=7.0.0
EOF

# Create README for context
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Data Processor Project

A Python project for data validation with pytest tests.

## Running Tests
