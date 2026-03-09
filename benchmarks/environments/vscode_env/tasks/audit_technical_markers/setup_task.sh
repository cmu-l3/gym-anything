#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Audit Technical Markers Task ==="

WORKSPACE="/home/ga/workspace/inventory-api"
sudo -u ga mkdir -p "$WORKSPACE/src" "$WORKSPACE/tests"

# Create Python project with scattered technical debt markers
cat > "$WORKSPACE/src/database.py" << 'EOF'
"""Database connection handling"""
import sqlite3

def connect_db(db_path):
    """Connect to SQLite database"""
    # TODO: Add connection pooling for better performance
    conn = sqlite3.connect(db_path)
    return conn

def execute_query(conn, query, params=None):
    """Execute a database query"""
    cursor = conn.cursor()
    # FIXME: This will fail if params is None - critical bug!
    cursor.execute(query, params)
    return cursor.fetchall()

def close_connection(conn):
    """Close database connection"""
    # HACK: Ignoring exceptions for now
    try:
        conn.close()
    except:
        pass
EOF

cat > "$WORKSPACE/src/api.py" << 'EOF'
"""REST API handlers"""
from flask import Flask, request, jsonify
import logging

app = Flask(__name__)

@app.route('/items', methods=['GET'])
def get_items():
    """Retrieve all items"""
    # TODO: Add pagination support for large result sets
    items = fetch_all_items()
    return jsonify(items)

@app.route('/items/<int:item_id>', methods=['GET'])
def get_item(item_id):
    """Retrieve single item"""
    item = fetch_item(item_id)
    if not item:
        # FIXME: Should return 404, currently returns 200 with empty body - critical!
        return jsonify({})
    return jsonify(item)

# XXX: This endpoint is untested and probably broken
@app.route('/items', methods=['POST'])
def create_item():
    data = request.get_json()
    # TODO: Add input validation before saving
    return jsonify({"status": "created"}), 201

def fetch_all_items():
    """Placeholder for database fetch"""
    return []

def fetch_item(item_id):
    """Placeholder for single item fetch"""
    return None
EOF

cat > "$WORKSPACE/src/validation.py" << 'EOF'
"""Input validation utilities"""
import re

def validate_email(email):
    """Validate email format"""
    # TODO: Use proper email validation library instead of regex
    pattern = r'^[\w\.-]+@[\w\.-]+\.\w+$'
    return re.match(pattern, email) is not None

def validate_price(price):
    """Validate price is positive number"""
    try:
        return float(price) > 0
    except ValueError:
        return False

def sanitize_input(text):
    """Sanitize user input"""
    # HACK: Basic sanitization, needs proper XSS prevention library
    return text.replace('<', '&lt;').replace('>', '&gt;')
EOF

cat > "$WORKSPACE/src/utils.py" << 'EOF'
"""Utility functions"""
import json

def load_config(path):
    """Load JSON configuration"""
    with open(path, 'r') as f:
        # TODO: Add error handling for missing files
        return json.load(f)

def format_response(data, status='success'):
    """Format API response"""
    # TODO: Add response timestamps for debugging
    return {
        'status': status,
        'data': data
    }

# Old code from previous version - keeping for reference
# TODO: Can we delete this legacy formatter?
# def legacy_formatter(data):
#     return str(data)
EOF

cat > "$WORKSPACE/tests/test_validation.py" << 'EOF'
"""Tests for validation module"""
import pytest
from src.validation import validate_email, validate_price

def test_validate_email():
    """Test email validation"""
    # TODO: Add more comprehensive test cases
    assert validate_email('test@example.com') == True
    assert validate_email('invalid') == False

def test_validate_price():
    """Test price validation"""
    assert validate_price(10.50) == True
    assert validate_price(-5) == False
EOF

cat > "$WORKSPACE/README.md" << 'EOF'
# Inventory API

A simple inventory management API.

## Development TODO
- Add authentication middleware
- Write comprehensive integration tests
- Deploy to production environment
EOF

cat > "$WORKSPACE/requirements.txt" << 'EOF'
flask==2.0.1
pytest==7.0.0
EOF

# Set ownership
sudo chown -R ga:ga "$WORKSPACE"

# Initialize git repo (for consistency with other tasks)
cd "$WORKSPACE"
sudo -u ga git init
sudo -u ga git config user.name "GA User"
sudo -u ga git config user.email "ga@localhost"
sudo -u ga git add .
sudo -u ga git commit -m "Initial commit with technical debt markers"

# Open VSCode with workspace
echo "Opening VSCode with workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Audit Technical Markers Task Setup Complete ==="
echo "📝 Workspace: $WORKSPACE"
echo "📝 Instructions:"
echo "  1. Use Search (Ctrl+Shift+F) to find TODO/FIXME/HACK/XXX markers"
echo "  2. Create TECHNICAL_DEBT.md with audit of all markers"
echo "  3. Fix critical bugs in src/database.py and src/api.py"
echo "  4. Save all files when complete"