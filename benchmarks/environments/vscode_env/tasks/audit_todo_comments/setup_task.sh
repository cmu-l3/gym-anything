#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Audit TODO Comments Task ==="

WORKSPACE_DIR="/home/ga/workspace/auth_service"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

# Create auth.py with TODO markers
cat > "$WORKSPACE_DIR/auth.py" << 'EOF'
"""
Authentication service for API gateway
"""
import hashlib
import time

# TODO: Add rate limiting to prevent brute force attacks
def authenticate_user(username, password):
    """Authenticate a user against the database"""
    # FIXME: This is using MD5 which is deprecated and insecure
    password_hash = hashlib.md5(password.encode()).hexdigest()
    
    # XXX: Direct database query without prepared statement - SQL injection risk!
    query = f"SELECT * FROM users WHERE username='{username}' AND password='{password_hash}'"
    
    # TODO: Implement proper session token generation
    return {"token": "placeholder_token", "expires": time.time() + 3600}


def verify_token(token):
    """Verify an authentication token"""
    # HACK: Just checking if token exists, no real verification
    if token and len(token) > 10:
        return True
    return False


# NOTE: This function needs comprehensive unit tests before production
def refresh_token(old_token):
    """Refresh an expired token"""
    if verify_token(old_token):
        # TODO: Check token expiration timestamp
        return authenticate_user("cached_user", "cached_pass")
    return None
EOF

# Create middleware.py with TODO markers
cat > "$WORKSPACE_DIR/middleware.py" << 'EOF'
"""
Middleware for handling authentication in requests
"""
from auth import verify_token

# FIXME: This middleware doesn't handle OPTIONS requests for CORS
def auth_middleware(request):
    """Extract and verify authentication from request headers"""
    token = request.headers.get('Authorization')
    
    if not token:
        # TODO: Return proper 401 with WWW-Authenticate header
        return {"error": "Unauthorized"}
    
    # XXX: Not handling Bearer token format correctly
    if verify_token(token):
        return {"status": "authorized"}
    
    return {"error": "Invalid token"}


# NOTE: Consider adding request logging for security audit trail
def log_auth_attempt(username, success):
    """Log authentication attempts"""
    # TODO: Implement actual logging instead of print
    print(f"Auth attempt: {username} - {'SUCCESS' if success else 'FAILED'}")
EOF

# Create config.py with TODO markers
cat > "$WORKSPACE_DIR/config.py" << 'EOF'
"""
Configuration for authentication service
"""
import os

# FIXME: These should be environment variables, not hardcoded
DATABASE_URL = "postgresql://localhost:5432/authdb"
SECRET_KEY = "not-so-secret-key-12345"

# TODO: Add configuration validation
# TODO: Support multiple environments (dev, staging, prod)

def get_config():
    """Get configuration settings"""
    return {
        "db_url": DATABASE_URL,
        "secret": SECRET_KEY,
        # HACK: Disabling SSL verification for local development
        "verify_ssl": False
    }
EOF

# Create test file with TODO markers
cat > "$WORKSPACE_DIR/tests/test_auth.py" << 'EOF'
"""
Tests for authentication service
"""
import unittest
from auth import authenticate_user, verify_token

# TODO: Add test for rate limiting
# TODO: Add test for password complexity requirements
# TODO: Add test for token expiration

class TestAuth(unittest.TestCase):
    def test_basic_auth(self):
        """Test basic authentication flow"""
        # FIXME: This test uses a hardcoded password
        result = authenticate_user("testuser", "testpass123")
        self.assertIsNotNone(result.get('token'))
    
    # NOTE: This test is incomplete and should cover edge cases
    def test_verify_token(self):
        """Test token verification"""
        self.assertTrue(verify_token("valid_token_here"))
        self.assertFalse(verify_token(""))
EOF

# Create README with TODO markers
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Authentication Service

API authentication microservice.

## Setup

TODO: Add installation instructions
TODO: Document environment variables

## Testing

Run tests with: `python -m pytest tests/`

FIXME: Current test coverage is below 50%
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Initialize git repo
cd "$WORKSPACE_DIR"
sudo -u ga git init
sudo -u ga git config user.email "dev@example.com"
sudo -u ga git config user.name "Developer"
sudo -u ga git add .
sudo -u ga git commit -m "Initial authentication service implementation"

# Open VSCode in the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' --new-window" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Audit TODO Comments Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Use Find in Files (Ctrl+Shift+F) to search for TODO markers"
echo "  2. Enable regex and search: TODO|FIXME|HACK|XXX|NOTE"
echo "  3. Create TODO_AUDIT.md documenting all findings"
echo "  4. Include file paths, line numbers, and comment text"
echo "  5. Add structure with markdown headers/bullets"
echo ""
echo "Workspace: $WORKSPACE_DIR"
echo "Files with TODOs: auth.py, middleware.py, config.py, tests/test_auth.py, README.md"