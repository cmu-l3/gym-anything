#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Review PR Locally Task ==="

WORKSPACE_DIR="/home/ga/workspace/auth-service"
TASK_ASSETS="/workspace/tasks/review_pr_locally/assets"

# Create workspace directory
sudo -u ga mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Initialize Git repository as ga user
sudo -u ga git init
sudo -u ga git config user.name "GA User"
sudo -u ga git config user.email "ga@localhost"

# Create src directory structure
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/auth"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

# Create initial __init__.py files
sudo -u ga touch "$WORKSPACE_DIR/src/__init__.py"
sudo -u ga touch "$WORKSPACE_DIR/src/auth/__init__.py"
sudo -u ga touch "$WORKSPACE_DIR/tests/__init__.py"

# Create original (vulnerable) validator.py
cat > "$WORKSPACE_DIR/src/auth/validator.py" << 'EOF'
import re

def sanitize_user_input(user_input):
    """
    Sanitize user input.
    Currently only strips whitespace.
    """
    if not user_input or not isinstance(user_input, str):
        return ""
    return user_input.strip()

def validate_email(email):
    """Basic email validation."""
    if not email:
        return False
    pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    return bool(re.match(pattern, email))
EOF

# Create login.py (unchanged in PR)
cat > "$WORKSPACE_DIR/src/auth/login.py" << 'EOF'
from .validator import sanitize_user_input, validate_email

def login(username, password):
    """Handle user login."""
    clean_username = sanitize_user_input(username)
    if not clean_username:
        return False, "Invalid username"
    
    # Placeholder for actual authentication
    return True, "Login successful"
EOF

# Create original test file
cat > "$WORKSPACE_DIR/tests/test_validator.py" << 'EOF'
import pytest
import sys
sys.path.insert(0, '/home/ga/workspace/auth-service')

from src.auth.validator import sanitize_user_input, validate_email

def test_sanitize_basic():
    assert sanitize_user_input("hello") == "hello"

def test_sanitize_strips_whitespace():
    assert sanitize_user_input("  hello  ") == "hello"

def test_validate_email():
    assert validate_email("user@example.com") == True
    assert validate_email("invalid") == False
EOF

# Create README
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Auth Service

Authentication and authorization service for the application.

## Modules

- `src/auth/validator.py` - Input validation and sanitization
- `src/auth/login.py` - Login handler
- `tests/test_validator.py` - Validation tests
EOF

# Set ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Create initial commit on main
cd "$WORKSPACE_DIR"
sudo -u ga git add .
sudo -u ga git commit -m "Initial commit: auth service base"

# Create and switch to PR branch
sudo -u ga git checkout -b fix/sanitize-user-input

# Modify validator.py with the security fix
cat > "$WORKSPACE_DIR/src/auth/validator.py" << 'EOF'
import re
import html

def sanitize_user_input(user_input):
    """
    Sanitize user input to prevent XSS and injection attacks.
    
    FIXED: Now properly escapes HTML entities and strips dangerous characters.
    Previously only stripped whitespace which was insufficient.
    """
    if not user_input or not isinstance(user_input, str):
        return ""
    
    # Strip leading/trailing whitespace
    sanitized = user_input.strip()
    
    # NEW: Escape HTML entities to prevent XSS
    sanitized = html.escape(sanitized)
    
    # NEW: Remove null bytes and control characters
    sanitized = re.sub(r'[\x00-\x1F\x7F]', '', sanitized)
    
    return sanitized

def validate_email(email):
    """Basic email validation."""
    if not email:
        return False
    pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    return bool(re.match(pattern, email))
EOF

# Update test file with new tests
cat > "$WORKSPACE_DIR/tests/test_validator.py" << 'EOF'
import pytest
import sys
sys.path.insert(0, '/home/ga/workspace/auth-service')

from src.auth.validator import sanitize_user_input, validate_email

def test_sanitize_basic():
    assert sanitize_user_input("hello") == "hello"

def test_sanitize_strips_whitespace():
    assert sanitize_user_input("  hello  ") == "hello"

def test_sanitize_escapes_html():
    """NEW TEST: Ensure HTML entities are escaped"""
    result = sanitize_user_input("<script>alert('xss')</script>")
    assert "<script>" not in result
    assert "&lt;script&gt;" in result

def test_sanitize_removes_control_chars():
    """NEW TEST: Control characters should be stripped"""
    result = sanitize_user_input("hello\x00world\x1F")
    assert "\x00" not in result
    assert result == "helloworld"

def test_validate_email():
    assert validate_email("user@example.com") == True
    assert validate_email("invalid") == False
EOF

# Also update README
cat >> "$WORKSPACE_DIR/README.md" << 'EOF'

## Recent Changes

- Fixed user input sanitization vulnerability (see PR #42)
EOF

# Commit changes on PR branch
sudo -u ga git add .
sudo -u ga git commit -m "Fix: Add HTML escaping and control char removal to input sanitization

Previously sanitize_user_input() only stripped whitespace, leaving
the application vulnerable to XSS attacks. This commit adds proper
HTML entity escaping and removes control characters.

Added test coverage for the new sanitization behavior.

Fixes #87"

# Switch back to main branch (agent needs to checkout fix/sanitize-user-input)
sudo -u ga git checkout main

# Ensure both branches exist
BRANCHES=$(sudo -u ga git branch)
echo "Available branches:"
echo "$BRANCHES"

# Open VSCode in workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Review PR Locally Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Current branch: main"
echo "  PR branch to review: fix/sanitize-user-input"
echo "  1. Check out the PR branch using Git"
echo "  2. Inspect changed files (validator.py, test_validator.py)"
echo "  3. Create pr_review_notes.txt with:"
echo "     - Branch name"
echo "     - Modified files list"
echo "     - Description of the fix"
echo "     - Whether tests were updated"