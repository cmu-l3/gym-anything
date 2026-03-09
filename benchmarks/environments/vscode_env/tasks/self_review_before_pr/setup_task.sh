#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Self Review Before PR Task ==="

WORKSPACE_DIR="/home/ga/workspace/auth_feature"
USER="ga"

# Create project structure
echo "Creating project structure..."
sudo -u $USER mkdir -p "$WORKSPACE_DIR/auth"
sudo -u $USER mkdir -p "$WORKSPACE_DIR/utils"
sudo -u $USER mkdir -p "$WORKSPACE_DIR/tests"

# Initialize git repository
echo "Initializing git repository..."
cd "$WORKSPACE_DIR"
sudo -u $USER git init
sudo -u $USER git config user.name "GA User"
sudo -u $USER git config user.email "ga@example.com"

# Create initial committed version (clean baseline)
echo "Creating initial clean baseline..."

cat > "$WORKSPACE_DIR/auth/login.py" <<'EOF'
"""
User login authentication module
"""

def authenticate_user(username, password):
    """Authenticate user credentials"""
    if not username or not password:
        return None
    
    # Validate user credentials
    user = get_user_from_db(username)
    
    if user and verify_password(user, password):
        return user
    
    return None


def get_user_from_db(username):
    """Fetch user from database"""
    # Database query logic here
    return {"username": username, "id": 123}


def verify_password(user, password):
    """Verify password hash"""
    # Password verification logic
    return True
EOF

cat > "$WORKSPACE_DIR/auth/user.py" <<'EOF'
"""
User model and validation
"""

class User:
    def __init__(self, username, email):
        self.username = username
        self.email = email
    
    def validate_email(self):
        """Validate email format"""
        return "@" in self.email
    
    def to_dict(self):
        """Convert user to dictionary"""
        return {
            "username": self.username,
            "email": self.email
        }
EOF

cat > "$WORKSPACE_DIR/utils/helpers.py" <<'EOF'
"""
Utility helper functions
"""

def format_username(username):
    """Format username for display"""
    return username.strip().lower()


def generate_token(user_id):
    """Generate authentication token"""
    import hashlib
    return hashlib.sha256(str(user_id).encode()).hexdigest()
EOF

cat > "$WORKSPACE_DIR/tests/test_auth.py" <<'EOF'
"""
Authentication tests
"""

def test_authenticate_valid_user():
    """Test authentication with valid credentials"""
    # Test implementation
    pass


def test_authenticate_invalid_user():
    """Test authentication with invalid credentials"""
    # Test implementation
    pass
EOF

sudo chown -R $USER:$USER "$WORKSPACE_DIR"

# Commit initial clean version
echo "Creating initial commit..."
cd "$WORKSPACE_DIR"
sudo -u $USER git add -A
sudo -u $USER git commit -m "Initial auth implementation"

# Now create the "working directory" with problems
echo "Adding problematic changes..."

cat > "$WORKSPACE_DIR/auth/login.py" <<'EOF'
"""
User login authentication module
"""

def authenticate_user(username, password):
    """Authenticate user credentials"""
    if not username or not password:
        return None
    
    # Validate user credentials
    user = get_user_from_db(username)
    
    # DEBUG: Remove this before PR!
    print("DEBUG: user object:", user)
    
    if user and verify_password(user, password):
        return user
    
    return None


def get_user_from_db(username):
    """Fetch user from database"""
    # Database query logic here
    return {"username": username, "id": 123}


def verify_password(user, password):
    """Verify password hash"""
    # Password verification logic
    return True
EOF

cat > "$WORKSPACE_DIR/auth/user.py" <<'EOF'
"""
User model and validation
"""

class User:
    def __init__(self, username, email):
        self.username = username
        self.email = email
    
    def validate_email(self):
        """Validate email format"""
        return "@" in self.email
    
    def validate_username(self):
        """Validate username format"""
        # TODO: This is hacky, refactor later
        return len(self.username) > 3
    
    def to_dict(self):
        """Convert user to dictionary"""
        return {
            "username": self.username,
            "email": self.email
        }
EOF

cat > "$WORKSPACE_DIR/utils/helpers.py" <<'EOF'
"""
Utility helper functions
"""
import pdb


def format_username(username):
    """Format username for display"""
    return username.strip().lower()


def generate_token(user_id):
    """Generate authentication token"""
    import hashlib
    return hashlib.sha256(str(user_id).encode()).hexdigest()


def debug_user_object(user):
    """Helper for debugging user objects"""
    return f"User: {user}"
EOF

cat > "$WORKSPACE_DIR/tests/test_auth.py" <<'EOF'
"""
Authentication tests
"""

def test_authenticate_valid_user():
    """Test authentication with valid credentials"""
    # Test implementation
    pass


def test_authenticate_invalid_user():
    """Test authentication with invalid credentials"""
    # Test implementation
    pass


def test_user_validation():
    """Test user validation methods"""
    # New test for validation
    pass
EOF

# Create the debug test file that should NOT be committed
cat > "$WORKSPACE_DIR/tests/test_debug.py" <<'EOF'
"""
Debug test file - DO NOT COMMIT
"""

def test_print_everything():
    print("This is just for debugging")
    print("Should not be in PR")
EOF

sudo chown -R $USER:$USER "$WORKSPACE_DIR"

# Stage all files (including the debug file) - simulating rushed work
echo "Staging all changes..."
cd "$WORKSPACE_DIR"
sudo -u $USER git add -A

# Create __init__.py files to make it a proper package
touch "$WORKSPACE_DIR/auth/__init__.py"
touch "$WORKSPACE_DIR/utils/__init__.py"
touch "$WORKSPACE_DIR/tests/__init__.py"
sudo chown -R $USER:$USER "$WORKSPACE_DIR"

# Open VSCode to the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open Source Control view (Ctrl+Shift+G)
echo "Opening Source Control view..."
sleep 1
su - ga -c "DISPLAY=:1 xdotool key ctrl+shift+g" || true
sleep 2

echo "=== Self Review Before PR Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Workspace: $WORKSPACE_DIR"
echo "  Git repo initialized with problematic changes staged"
echo "  Issues to fix:"
echo "    1. Debug print in auth/login.py"
echo "    2. Vague TODO in auth/user.py"
echo "    3. Unused 'import pdb' in utils/helpers.py"
echo "    4. Delete or unstage tests/test_debug.py"
echo ""
echo "  Source Control view should be open"
echo "  Review diffs and fix issues before PR"