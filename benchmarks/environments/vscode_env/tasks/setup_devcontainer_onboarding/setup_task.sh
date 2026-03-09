#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up DevContainer Onboarding Task ==="

WORKSPACE_DIR="/home/ga/workspace/team_project"
sudo -u ga mkdir -p "$WORKSPACE_DIR"/{src,tests}

# Create Python source files
cat > "$WORKSPACE_DIR/src/__init__.py" << 'EOF'
"""Team project package"""
__version__ = "0.1.0"
EOF

cat > "$WORKSPACE_DIR/src/main.py" << 'EOF'
"""FastAPI application"""
from fastapi import FastAPI

app = FastAPI(title="Team Project API")

@app.get("/")
def read_root():
    return {"message": "Hello, World!"}

@app.get("/health")
def health_check():
    return {"status": "healthy"}

@app.get("/api/users")
def list_users():
    return {"users": []}
EOF

cat > "$WORKSPACE_DIR/src/models.py" << 'EOF'
"""Database models"""
from sqlalchemy import Column, Integer, String
from sqlalchemy.ext.declarative import declarative_base

Base = declarative_base()

class User(Base):
    __tablename__ = "users"
    
    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True)
    name = Column(String)
    
    def __repr__(self):
        return f"<User(email='{self.email}', name='{self.name}')>"
EOF

# Create test files
cat > "$WORKSPACE_DIR/tests/__init__.py" << 'EOF'
"""Tests package"""
EOF

cat > "$WORKSPACE_DIR/tests/test_api.py" << 'EOF'
"""API tests"""
from fastapi.testclient import TestClient
from src.main import app

client = TestClient(app)

def test_read_root():
    response = client.get("/")
    assert response.status_code == 200
    assert "message" in response.json()

def test_health_check():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"

def test_list_users():
    response = client.get("/api/users")
    assert response.status_code == 200
    assert "users" in response.json()
EOF

# Create requirements.txt
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
fastapi==0.109.0
uvicorn[standard]==0.27.0
sqlalchemy==2.0.25
pytest==7.4.4
httpx==0.26.0
black==24.1.1
pylint==3.0.3
EOF

# Create .gitignore
cat > "$WORKSPACE_DIR/.gitignore" << 'EOF'
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
.venv/
venv/
ENV/
env/
.pytest_cache/
.coverage
htmlcov/
*.db
*.sqlite3
.vscode/.env
.DS_Store
EOF

# Create README.md
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Team Project

A FastAPI-based backend service for our growing startup.

## Tech Stack

- **Python 3.11** - Modern Python
- **FastAPI** - High-performance web framework  
- **PostgreSQL** - Production database
- **Pytest** - Testing framework
- **Black** - Code formatter (88 char line length)
- **Pylint** - Code linter

## Project Structure
