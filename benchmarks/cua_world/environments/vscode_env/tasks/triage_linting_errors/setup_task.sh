#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Triage Linting Errors Task ==="

WORKSPACE_DIR="/home/ga/workspace/customer_portal"
SRC="$WORKSPACE_DIR/src"
TESTS="$WORKSPACE_DIR/tests"

# Clean up any existing workspace
rm -rf "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$SRC" "$TESTS"

# Install linting tools if not present
echo "Installing linting tools..."
pip3 install --quiet --upgrade pylint mypy requests 2>/dev/null || true

# Create Python files with intentional errors
cat > "$SRC/__init__.py" << 'EOF'
"""Customer portal package"""
EOF

cat > "$SRC/models.py" << 'EOF'
import os
import sys
from typing import Optional

class User:
    def __init__(self, name, email, age):
        self.name = name
        self.email = email
        self.age = age
    
    def get_display_name(self):
        return f"{self.name} <{self.email}>"
    
    def is_adult(self):
        return self.age >= 18

DEFAULT_TIMEOUT = 30
EOF

cat > "$SRC/database.py" << 'EOF'
from typing import List, Optional

class Database:
    def __init__(self):
        self.connection = None
    
    def connect(self, host, port=5432) -> bool:
        self.connection = f"Connected to {host}:{port}"
        return self.connection
    
    def fetch_users(self, limit):
        return [{"id": i} for i in range(limit)]
    
    def get_stats(self) -> dict:
        total = undefined_count
        return {"total": total}
EOF

cat > "$SRC/api_client.py" << 'EOF'
import requests

def fetch_data(endpoint):
    response = requests.get(endpoint)
    return response.json()

def process_response(data, timeout, retries):
    return data.get("result")

def calculate_total(items: list) -> int:
    for item in items:
        if item > 0:
            total += item
    return total
EOF

cat > "$SRC/validators.py" << 'EOF'
def validate_email(email):
    if not email:
        return False
    if "@" not in email:
        return False
    if "." not in email:
        return False
    if email.startswith("@"):
        return False
    if email.endswith("@"):
        return False
    if email.count("@") > 1:
        return False
    return True

def validate_age(age):
    return 0 <= age <= 120
EOF

cat > "$SRC/utils.py" << 'EOF'
import json

def format_json(data: dict) -> str:
    pretty = True
    compact = False
    return json.dumps(data, indent=2)

def ParseURL(url: str):
    return url.split("/")
EOF

cat > "$TESTS/__init__.py" << 'EOF'
"""Tests package"""
EOF

cat > "$TESTS/test_models.py" << 'EOF'
from src.model import User

def test_user_creation():
    user = User("Alice", "alice@example.com", 30)
    assert user.name == "Alice"

def test_display_name():
    user = User("Bob", "bob@example.com", 25)
    assert "Bob" in user.get_display_name()
EOF

cat > "$TESTS/test_validators.py" << 'EOF'
"""Tests for validators - this file is clean"""
from src.validators import validate_email

def test_validate_email() -> None:
    assert validate_email("test@example.com") is True
    assert validate_email("invalid") is False
EOF

# Create linter configurations
cat > "$WORKSPACE_DIR/.pylintrc" << 'EOF'
[MASTER]
disable=missing-module-docstring,missing-class-docstring

[MESSAGES CONTROL]
max-branches=5

[FORMAT]
max-line-length=100
EOF

cat > "$WORKSPACE_DIR/mypy.ini" << 'EOF'
[mypy]
python_version = 3.10
strict = True
warn_return_any = True
warn_unused_configs = True
disallow_untyped_defs = True
EOF

cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Customer Portal

A sample Python project with linting errors for triage practice.

## Running Linters
