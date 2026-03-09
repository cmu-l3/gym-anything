#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Integrate Custom Linter Task ==="

WORKSPACE_DIR="/home/ga/workspace/medscan_project"
ASSETS_DIR="/workspace/tasks/integrate_custom_linter/assets"

# Create workspace structure
sudo -u ga mkdir -p "$WORKSPACE_DIR/src"
sudo -u ga mkdir -p "$WORKSPACE_DIR/.vscode"

# Copy sample Python files with security issues
echo "Creating sample files with security issues..."

cat > "$WORKSPACE_DIR/src/auth.py" << 'EOF'
import sqlite3

class AuthManager:
    def __init__(self, db_path):
        self.conn = sqlite3.connect(db_path)
    
    def authenticate(self, username, password):
        cursor = self.conn.cursor()
        # Vulnerable to SQL injection
        query = f"SELECT * FROM users WHERE username='{username}' AND password='{password}'"
        cursor.execute(query)
        result = cursor.fetchone()
        return result is not None
    
    def get_user_data(self, user_id):
        cursor = self.conn.cursor()
        # Another SQL injection vulnerability
        query = "SELECT * FROM users WHERE id=" + str(user_id)
        cursor.execute(query)
        return cursor.fetchone()
EOF

cat > "$WORKSPACE_DIR/src/api.py" << 'EOF'
import requests
from flask import Flask, request

app = Flask(__name__)

# Hardcoded credentials (security issue)
API_KEY = "sk_live_1234567890abcdef"
DATABASE_PASSWORD = "MySecretPass123"

@app.route('/data')
def get_data():
    # Using hardcoded API key
    headers = {"Authorization": f"Bearer {API_KEY}"}
    response = requests.get("https://api.example.com/data", headers=headers)
    return response.json()

@app.route('/admin')
def admin_panel():
    # Hardcoded password check
    if request.args.get('password') == DATABASE_PASSWORD:
        return "Admin access granted"
    return "Access denied"
EOF

cat > "$WORKSPACE_DIR/src/utils.py" << 'EOF'
import pickle
import yaml

def load_config(config_file):
    # Unsafe deserialization
    with open(config_file, 'rb') as f:
        return pickle.load(f)

def parse_yaml(yaml_string):
    # Unsafe YAML loading
    return yaml.load(yaml_string)

def execute_command(user_input):
    # Command injection vulnerability
    import os
    os.system(f"echo {user_input}")
EOF

# Copy TASK.md instructions
cat > "$WORKSPACE_DIR/TASK.md" << 'EOF'
# Task: Integrate Custom Security Linter

## Objective
Integrate the `medscan` security linter into VSCode so violations appear in the Problems panel.

## Linter Location
`/workspace/tasks/integrate_custom_linter/assets/medscan.sh`

## Linter Output Format