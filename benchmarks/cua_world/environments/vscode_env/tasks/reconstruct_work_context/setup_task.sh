#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Reconstruct Work Context Task ==="

WORKSPACE_DIR="/home/ga/workspace/myproject"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Initialize Git repository
echo "Initializing Git repository..."
sudo -u ga git init
sudo -u ga git config user.name "GA User"
sudo -u ga git config user.email "ga@example.com"

# Create project structure
sudo -u ga mkdir -p src/api src/models src/utils tests

# Create initial files with base content
echo "Creating project files..."

cat > "$WORKSPACE_DIR/src/api/user_routes.py" << 'EOF'
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/users', methods=['POST'])
def create_user():
    data = request.get_json()
    # Basic user creation
    return jsonify({"status": "success"}), 201

@app.route('/users/<int:user_id>', methods=['GET'])
def get_user(user_id):
    return jsonify({"id": user_id, "name": "Test User"})
EOF

cat > "$WORKSPACE_DIR/src/api/validators.py" << 'EOF'
import re

def validate_email(email):
    """Basic email validation"""
    pattern = r'^[\w\.-]+@[\w\.-]+\.\w+$'
    return re.match(pattern, email) is not None
EOF

cat > "$WORKSPACE_DIR/src/models/user.py" << 'EOF'
class User:
    def __init__(self, email, username):
        self.email = email
        self.username = username
    
    def to_dict(self):
        return {
            'email': self.email,
            'username': self.username
        }
EOF

cat > "$WORKSPACE_DIR/src/utils/helpers.py" << 'EOF'
def format_response(data, status="success"):
    return {"status": status, "data": data}
EOF

cat > "$WORKSPACE_DIR/tests/test_user_routes.py" << 'EOF'
import pytest

def test_create_user():
    # Basic test
    assert True
EOF

cat > "$WORKSPACE_DIR/tests/test_validators.py" << 'EOF'
import pytest

def test_validate_email():
    # Basic test
    assert True
EOF

cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# User Management API

A simple user management API with Flask.
EOF

cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
flask==2.3.0
pytest==7.4.0
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Initial commit
echo "Creating initial commit..."
cd "$WORKSPACE_DIR"
sudo -u ga git add -A
sudo -u ga git commit -m "Initial project setup"

# Create feature branch
echo "Creating feature branch..."
sudo -u ga git checkout -b feature/user-validation

# Now modify files to simulate work in progress
echo "Simulating work in progress..."

cat > "$WORKSPACE_DIR/src/api/user_routes.py" << 'EOF'
from flask import Flask, request, jsonify
from validators import validate_user_data

app = Flask(__name__)

@app.route('/users', methods=['POST'])
def create_user():
    data = request.get_json()
    # TODO: Add comprehensive input validation
    # TODO: Add rate limiting for user creation
    user_data = validate_user_data(data)
    # Save to database...
    return jsonify({"status": "success"}), 201

@app.route('/users/<int:user_id>', methods=['GET'])
def get_user(user_id):
    # FIXME: Add error handling for non-existent users
    # FIXME: Add authentication check
    return jsonify({"id": user_id, "name": "Test User"})

@app.route('/users/<int:user_id>', methods=['PUT'])
def update_user(user_id):
    # TODO: Implement user update logic
    pass
EOF

cat > "$WORKSPACE_DIR/src/api/validators.py" << 'EOF'
import re

def validate_user_data(data):
    """Validate user input data"""
    errors = []
    
    # Email validation
    if 'email' not in data:
        errors.append("Email is required")
    elif not re.match(r'^[\w\.-]+@[\w\.-]+\.\w+$', data['email']):
        errors.append("Invalid email format")
    
    # TODO: Add password strength validation (min 8 chars, special chars)
    # TODO: Add username uniqueness check against database
    # FIXME: Email validation regex is too permissive, allows invalid domains
    
    # Username validation
    if 'username' in data:
        if len(data['username']) < 3:
            errors.append("Username must be at least 3 characters")
    
    if errors:
        raise ValueError(f"Validation errors: {', '.join(errors)}")
    
    return data

def validate_email(email):
    """Basic email validation"""
    # FIXME: This function is redundant with validate_user_data
    pattern = r'^[\w\.-]+@[\w\.-]+\.\w+$'
    return re.match(pattern, email) is not None
EOF

cat > "$WORKSPACE_DIR/src/models/user.py" << 'EOF'
class User:
    def __init__(self, email, username, password=None):
        self.email = email
        self.username = username
        self.password = password  # TODO: Hash passwords before storing (use bcrypt)
    
    def to_dict(self):
        return {
            'email': self.email,
            'username': self.username
        }
    
    def validate(self):
        # TODO: Add model-level validation
        # TODO: Check email format
        # TODO: Ensure username is not empty
        pass
EOF

cat > "$WORKSPACE_DIR/tests/test_user_routes.py" << 'EOF'
import pytest
from src.api.user_routes import app

@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

def test_create_user_success(client):
    response = client.post('/users', json={
        'email': 'test@example.com',
        'username': 'testuser'
    })
    assert response.status_code == 201

def test_create_user_invalid_email(client):
    # FIXME: This test is currently failing - validation not working properly
    response = client.post('/users', json={
        'email': 'invalid-email',
        'username': 'testuser'
    })
    assert response.status_code == 400  # Expected but not working

def test_get_user(client):
    response = client.get('/users/1')
    assert response.status_code == 200
    # TODO: Add assertions for response data structure
EOF

cat > "$WORKSPACE_DIR/tests/test_validators.py" << 'EOF'
import pytest
from src.api.validators import validate_user_data, validate_email

def test_valid_email():
    data = {'email': 'test@example.com', 'username': 'testuser'}
    assert validate_user_data(data) == data

def test_missing_email():
    # TODO: Add more comprehensive test cases for edge cases
    with pytest.raises(ValueError):
        validate_user_data({'username': 'testuser'})

def test_short_username():
    # TODO: This test needs to verify the exact error message
    with pytest.raises(ValueError):
        validate_user_data({'email': 'test@example.com', 'username': 'ab'})

def test_validate_email_function():
    assert validate_email('test@example.com') == True
    assert validate_email('invalid') == False
    # FIXME: Add test for edge cases like multiple @ symbols
EOF

cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# User Management API

A simple user management API with Flask.

## Feature in Development: User Validation

Currently implementing comprehensive user input validation.
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Stage only some files (to simulate partial work)
echo "Staging partial changes..."
cd "$WORKSPACE_DIR"
sudo -u ga git add src/models/user.py
sudo -u ga git add README.md

# Leave other files unstaged
echo "Modified files status:"
sudo -u ga git status

# Open VSCode with the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 25
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Reconstruct Work Context Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Investigate workspace state:"
echo "     - Run 'git status' and 'git diff' in terminal"
echo "     - Use Source Control view (Ctrl+Shift+G)"
echo "  2. Search for TODO/FIXME comments (Ctrl+Shift+F)"
echo "  3. Review modified files to understand changes"
echo "  4. Create WORK_CONTEXT.md in workspace root with:"
echo "     - Modified Files section"
echo "     - Outstanding TODOs section"
echo "     - Current Status section"
echo "     - Next Steps section"
echo ""
echo "Workspace: $WORKSPACE_DIR"
echo "Branch: feature/user-validation"
echo "Modified files: user_routes.py, validators.py, user.py, test files"