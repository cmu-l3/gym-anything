#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Pre-Commit Hooks Task ==="

WORKSPACE_DIR="/home/ga/workspace/myapp"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

# Initialize Git repository
cd "$WORKSPACE_DIR"
sudo -u ga git init
sudo -u ga git config user.name "GA User"
sudo -u ga git config user.email "ga@localhost"

# Create source files with intentional issues (bad formatting, debug statements, secrets)
cat > "$WORKSPACE_DIR/src/__init__.py" << 'EOF'
"""MyApp package"""
__version__ = "0.1.0"
EOF

cat > "$WORKSPACE_DIR/src/app.py" << 'EOF'
from flask import Flask,jsonify
import os

app=Flask(__name__)

@app.route('/api/health')
def health():
    print("Health check called")
    return jsonify({"status":"ok"})

@app.route('/api/data')
def get_data( ):
    api_key = "sk-1234567890abcdef"
    return jsonify({"message":"data"})

if __name__=="__main__":
    app.run(debug=True)
EOF

cat > "$WORKSPACE_DIR/src/models.py" << 'EOF'
"""Database models"""

class User:
    def __init__(self,username,email):
        self.username=username
        self.email=email
    
    def __repr__(self):
        return f"<User {self.username}>"

class Product:
    def __init__(self,name,price):
        self.name=name
        self.price=price
    
    def get_price_with_tax(self,tax_rate=0.1):
        return self.price*(1+tax_rate)
EOF

cat > "$WORKSPACE_DIR/src/utils.py" << 'EOF'
"""Utility functions"""


def calculate_total(items):
    """Calculate total price of items"""
    return sum(item.get('price', 0) for item in items)


def format_currency(amount):
    """Format amount as currency"""
    return f"${amount:.2f}"


def validate_email(email):
    """Basic email validation"""
    return '@' in email and '.' in email.split('@')[1]
EOF

# Create test files
cat > "$WORKSPACE_DIR/tests/__init__.py" << 'EOF'
"""Tests package"""
EOF

cat > "$WORKSPACE_DIR/tests/test_app.py" << 'EOF'
import pytest
from src.app import app


def test_health():
    client = app.test_client()
    response = client.get('/api/health')
    assert response.status_code == 200
    assert response.json['status'] == 'ok'


def test_data():
    client = app.test_client()
    response = client.get('/api/data')
    assert response.status_code == 200
EOF

cat > "$WORKSPACE_DIR/tests/test_models.py" << 'EOF'
from src.models import User, Product


def test_user_creation():
    user = User("testuser", "test@example.com")
    assert user.username == "testuser"
    assert user.email == "test@example.com"


def test_product_price():
    product = Product("Widget", 100.0)
    assert product.get_price_with_tax() == 110.0
EOF

# Create requirements.txt (without pre-commit initially)
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
flask==2.3.0
pytest==7.4.0
requests==2.31.0
EOF

# Create README
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# MyApp

A simple Flask application for demonstration.

## Setup
