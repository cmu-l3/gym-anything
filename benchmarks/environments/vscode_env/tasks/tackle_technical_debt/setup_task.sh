#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Tackle Technical Debt Task ==="

WORKSPACE_DIR="/home/ga/workspace/webservice"
TASK_DIR="/workspace/tasks/tackle_technical_debt"

# Create workspace directory
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$WORKSPACE_DIR/routes"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

# Create app.py
cat > "$WORKSPACE_DIR/app.py" << 'EOF'
"""
Main Flask application for web service
"""
from flask import Flask
from routes import users, products

app = Flask(__name__)

# Register blueprints
app.register_blueprint(users.bp)
app.register_blueprint(products.bp)

if __name__ == '__main__':
    app.run(debug=True, port=5000)
EOF

# Create routes/__init__.py
cat > "$WORKSPACE_DIR/routes/__init__.py" << 'EOF'
"""Routes package"""
EOF

# Create routes/users.py with TODO
cat > "$WORKSPACE_DIR/routes/users.py" << 'EOF'
"""
User management routes
"""
from flask import Blueprint, jsonify, request

bp = Blueprint('users', __name__, url_prefix='/api')

@bp.route('/v2/users', methods=['GET'])
def get_users_v2():
    """Get all users - current API version"""
    users = [
        {'id': 1, 'name': 'Alice', 'email': 'alice@example.com'},
        {'id': 2, 'name': 'Bob', 'email': 'bob@example.com'}
    ]
    return jsonify(users)

# TODO: Remove this deprecated endpoint - it's been superseded by /api/v2/users
# This endpoint uses old response format and should be deleted by end of Q4
@bp.route('/v1/users', methods=['GET'])
def get_users_v1():
    """DEPRECATED: Use /api/v2/users instead"""
    users = [
        {'user_id': 1, 'user_name': 'Alice'},
        {'user_id': 2, 'user_name': 'Bob'}
    ]
    return jsonify(users)

@bp.route('/v2/users/<int:user_id>', methods=['GET'])
def get_user(user_id):
    """Get specific user"""
    user = {'id': user_id, 'name': 'Sample User', 'email': 'user@example.com'}
    return jsonify(user)
EOF

# Create routes/products.py
cat > "$WORKSPACE_DIR/routes/products.py" << 'EOF'
"""
Product management routes
"""
from flask import Blueprint, jsonify

bp = Blueprint('products', __name__, url_prefix='/api/v2')

@bp.route('/products', methods=['GET'])
def get_products():
    """Get all products"""
    products = [
        {'id': 1, 'name': 'Widget', 'price': 19.99},
        {'id': 2, 'name': 'Gadget', 'price': 29.99}
    ]
    return jsonify(products)
EOF

# Create database.py with FIXME
cat > "$WORKSPACE_DIR/database.py" << 'EOF'
"""
Database connection and query utilities
"""
import sqlite3
from typing import List, Dict, Any

DB_PATH = '/tmp/webservice.db'

def get_connection():
    """Get database connection"""
    return sqlite3.connect(DB_PATH)

def execute_query(query: str, params: tuple = ()) -> List[Dict[str, Any]]:
    """
    Execute a database query and return results
    
    FIXME: This has no error handling! If the database is locked or query is malformed,
    the entire application crashes. Need to add proper try-except with logging.
    """
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute(query, params)
    results = cursor.fetchall()
    conn.close()
    return results

def initialize_database():
    """Initialize database schema"""
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            email TEXT UNIQUE NOT NULL
        )
    ''')
    conn.commit()
    conn.close()
EOF

# Create utils.py with HACK
cat > "$WORKSPACE_DIR/utils.py" << 'EOF'
"""
Utility functions for the web service
"""
from datetime import datetime

def format_timestamp(dt: datetime) -> str:
    """Format datetime to ISO string"""
    return dt.isoformat()

def get_current_utc_timestamp() -> str:
    """
    Get current UTC timestamp
    
    HACK: This is a terrible way to handle timezones. We're manually stripping
    and appending 'Z' to force UTC. Should use pytz library properly:
    - from datetime import timezone
    - datetime.now(timezone.utc).isoformat()
    
    This breaks when datetime already has timezone info!
    """
    now = datetime.now()
    # This is the hack: just add 'Z' to pretend it's UTC
    timestamp = now.strftime('%Y-%m-%dT%H:%M:%S') + 'Z'
    return timestamp

def validate_email(email: str) -> bool:
    """Basic email validation"""
    return '@' in email and '.' in email.split('@')[1]
EOF

# Create requirements.txt
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
flask==2.3.0
EOF

# Create a simple test file
cat > "$WORKSPACE_DIR/tests/test_app.py" << 'EOF'
"""
Basic tests for the web service
"""
import unittest

class TestApp(unittest.TestCase):
    def test_placeholder(self):
        """Placeholder test"""
        self.assertTrue(True)

if __name__ == '__main__':
    unittest.main()
EOF

# Set ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Initialize git repository
cd "$WORKSPACE_DIR"
sudo -u ga git init
sudo -u ga git config user.name "GA User"
sudo -u ga git config user.email "ga@localhost"
sudo -u ga git add .
sudo -u ga git commit -m "Initial commit with technical debt"

# Open VSCode with the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' --disable-workspace-trust" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Tackle Technical Debt Task Setup Complete ==="
echo "📝 Workspace: $WORKSPACE_DIR"
echo "📝 Instructions:"
echo "  1. Use Ctrl+Shift+F to search for TODO, FIXME, and HACK comments"
echo "  2. Remove deprecated /api/v1/users endpoint in routes/users.py"
echo "  3. Add error handling to database.py execute_query function"
echo "  4. Fix timezone handling in utils.py"
echo "  5. Create CHANGELOG.md documenting all changes"
echo "  6. Save all files (Ctrl+S)"