#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Investigate Legacy Utility Task ==="

WORKSPACE_DIR="/home/ga/workspace"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create directory structure
sudo -u ga mkdir -p "$WORKSPACE_DIR/app/auth"
sudo -u ga mkdir -p "$WORKSPACE_DIR/app/api"
sudo -u ga mkdir -p "$WORKSPACE_DIR/app/utils"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

cd "$WORKSPACE_DIR"

# Initialize Git repository
sudo -u ga git init
sudo -u ga git config user.name "Legacy Developer"
sudo -u ga git config user.email "dev@company.com"

# Create initial project files (pre-2019)
cat > "$WORKSPACE_DIR/app/__init__.py" << 'EOF'
"""Web application package"""
EOF

cat > "$WORKSPACE_DIR/app/auth/__init__.py" << 'EOF'
"""Authentication module"""
EOF

cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Web Application

A Python web application for user management.
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"
sudo -u ga git add .
GIT_AUTHOR_DATE="2019-01-15T10:00:00" GIT_COMMITTER_DATE="2019-01-15T10:00:00" \
  sudo -u ga git commit -m "Initial project setup"

# Commit 1: Original sanitize_user_input in login.py (2019-06-15) - THE CRITICAL COMMIT
cat > "$WORKSPACE_DIR/app/auth/login.py" << 'EOF'
"""Login authentication module"""
import re

def sanitize_user_input(user_input):
    """
    Sanitize user input to prevent SQL injection attacks.
    Added after security incident June 2019.
    """
    # Remove dangerous SQL characters
    dangerous_chars = ["'", '"', ";", "--", "/*", "*/", "xp_", "sp_"]
    cleaned = user_input
    for char in dangerous_chars:
        cleaned = cleaned.replace(char, "")
    return cleaned.strip()

def authenticate_user(username, password):
    """Authenticate user credentials"""
    clean_username = sanitize_user_input(username)
    clean_password = sanitize_user_input(password)
    # Authentication logic here
    return True
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"
sudo -u ga git add app/auth/login.py
GIT_AUTHOR_DATE="2019-06-15T14:30:00" GIT_COMMITTER_DATE="2019-06-15T14:30:00" \
  sudo -u ga git commit -m "Fix SQL injection vulnerability in user input - Critical security patch for reported injection attack"

# Commit 2: Add sanitization to registration (2019-06-20)
cat > "$WORKSPACE_DIR/app/auth/registration.py" << 'EOF'
"""User registration module"""
import re

def sanitize_user_input(user_input):
    """
    Sanitize user input for registration forms.
    Additional protection against injection attacks.
    """
    # Similar to login sanitization but with extra validation
    dangerous_chars = ["'", '"', ";", "--", "/*", "*/", "xp_", "sp_", "drop", "delete"]
    cleaned = user_input.lower()
    for char in dangerous_chars:
        cleaned = cleaned.replace(char, "")
    return cleaned.strip()

def register_user(username, email, password):
    """Register new user"""
    clean_username = sanitize_user_input(username)
    clean_email = sanitize_user_input(email)
    # Registration logic
    return {"status": "success", "username": clean_username}
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"
sudo -u ga git add app/auth/registration.py
GIT_AUTHOR_DATE="2019-06-20T09:15:00" GIT_COMMITTER_DATE="2019-06-20T09:15:00" \
  sudo -u ga git commit -m "Add additional sanitization for registration form"

# Commit 3: Some unrelated commits
cat > "$WORKSPACE_DIR/app/models.py" << 'EOF'
"""Database models"""

class User:
    def __init__(self, username, email):
        self.username = username
        self.email = email
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"
sudo -u ga git add app/models.py
GIT_AUTHOR_DATE="2020-03-10T11:00:00" GIT_COMMITTER_DATE="2020-03-10T11:00:00" \
  sudo -u ga git commit -m "Add user models"

# Commit 4: Extract to utils (2021-03-10) - REFACTORING
cat > "$WORKSPACE_DIR/app/utils/__init__.py" << 'EOF'
"""Utility functions"""
EOF

cat > "$WORKSPACE_DIR/app/utils/validators.py" << 'EOF'
"""Input validation utilities"""
import re

def sanitize_user_input(user_input):
    """
    Canonical implementation of input sanitization.
    Extracted from auth modules for reusability.
    
    Protects against SQL injection by removing dangerous characters.
    See security incident report from June 2019.
    """
    if not user_input:
        return ""
    
    # Remove SQL injection vectors
    dangerous_patterns = ["'", '"', ";", "--", "/*", "*/", "xp_", "sp_", 
                         "drop", "delete", "insert", "update", "exec"]
    cleaned = str(user_input)
    for pattern in dangerous_patterns:
        cleaned = cleaned.replace(pattern, "")
    
    return cleaned.strip()

def validate_email(email):
    """Validate email format"""
    pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    return re.match(pattern, email) is not None
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"
sudo -u ga git add app/utils/
GIT_AUTHOR_DATE="2021-03-10T15:45:00" GIT_COMMITTER_DATE="2021-03-10T15:45:00" \
  sudo -u ga git commit -m "Extract sanitize_user_input to utils.validators for reusability"

# Commit 5: Add tests (2021-03-15)
cat > "$WORKSPACE_DIR/tests/__init__.py" << 'EOF'
"""Test suite"""
EOF

cat > "$WORKSPACE_DIR/tests/test_validators.py" << 'EOF'
"""Tests for validation utilities"""
import sys
sys.path.insert(0, '/home/ga/workspace')

from app.utils.validators import sanitize_user_input, validate_email

def test_sanitize_basic():
    """Test basic sanitization"""
    assert sanitize_user_input("hello") == "hello"
    assert sanitize_user_input("hello'world") == "helloworld"

def test_sanitize_sql_injection():
    """Test SQL injection prevention"""
    malicious = "admin'--"
    result = sanitize_user_input(malicious)
    assert "'" not in result
    assert "--" not in result

def test_validate_email():
    """Test email validation"""
    assert validate_email("user@example.com") == True
    assert validate_email("invalid.email") == False

if __name__ == "__main__":
    test_sanitize_basic()
    test_sanitize_sql_injection()
    test_validate_email()
    print("All tests passed!")
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"
sudo -u ga git add tests/
GIT_AUTHOR_DATE="2021-03-15T10:20:00" GIT_COMMITTER_DATE="2021-03-15T10:20:00" \
  sudo -u ga git commit -m "Add test coverage for validators"

# Commit 6: More unrelated work
cat > "$WORKSPACE_DIR/app/config.py" << 'EOF'
"""Application configuration"""

DATABASE_URL = "postgresql://localhost/webapp"
SECRET_KEY = "change-me-in-production"
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"
sudo -u ga git add app/config.py
GIT_AUTHOR_DATE="2023-07-20T13:00:00" GIT_COMMITTER_DATE="2023-07-20T13:00:00" \
  sudo -u ga git commit -m "Add configuration module"

# Commit 7: API endpoints using the utility (2024-11-01)
cat > "$WORKSPACE_DIR/app/api/__init__.py" << 'EOF'
"""API module"""
EOF

cat > "$WORKSPACE_DIR/app/api/endpoints.py" << 'EOF'
"""REST API endpoints"""
from app.utils.validators import sanitize_user_input

def create_user_endpoint(request_data):
    """
    API endpoint for user creation.
    Uses sanitize_user_input from utils.
    """
    username = sanitize_user_input(request_data.get('username', ''))
    email = sanitize_user_input(request_data.get('email', ''))
    
    return {
        "status": "success",
        "user": {
            "username": username,
            "email": email
        }
    }

def search_users_endpoint(query):
    """Search users by query"""
    clean_query = sanitize_user_input(query)
    # Search logic here
    return []
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"
sudo -u ga git add app/api/
GIT_AUTHOR_DATE="2024-11-01T16:30:00" GIT_COMMITTER_DATE="2024-11-01T16:30:00" \
  sudo -u ga git commit -m "Add API endpoint with input validation"

# Commit 8: Recent unrelated work
cat > "$WORKSPACE_DIR/.gitignore" << 'EOF'
__pycache__/
*.pyc
.env
venv/
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"
sudo -u ga git add .gitignore
GIT_AUTHOR_DATE="2025-01-10T09:00:00" GIT_COMMITTER_DATE="2025-01-10T09:00:00" \
  sudo -u ga git commit -m "Add gitignore"

echo "Git history created with $(sudo -u ga git log --oneline | wc -l) commits"

# Open VSCode with the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Investigate Legacy Utility Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Use Git commands to investigate sanitize_user_input() history"
echo "     - git log --grep='sanitize\|injection'"
echo "     - git blame app/auth/login.py"
echo "     - git show <commit-hash>"
echo "  2. Use VSCode Find All References (Shift+F12) on sanitize_user_input"
echo "  3. Navigate to all locations where function exists"
echo "  4. Check tests/ directory for test coverage"
echo "  5. Create /home/ga/workspace/ARCHAEOLOGY_REPORT.md with findings:"
echo "     - Historical Context (when introduced, why, commit message)"
echo "     - Current State (all locations, usage, tests)"
echo "     - Recommendation (keep/refactor/remove)"