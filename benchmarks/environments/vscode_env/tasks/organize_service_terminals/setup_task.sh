#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Organize Service Terminals Task ==="

# Install tesseract-ocr for screenshot verification if not installed
if ! command -v tesseract &> /dev/null; then
    echo "Installing tesseract-ocr for verification..."
    apt-get update -qq
    apt-get install -y -qq tesseract-ocr > /dev/null 2>&1
    echo "✅ tesseract-ocr installed"
fi

WORKSPACE_DIR="/home/ga/workspace/microservices_project"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create microservices project structure
echo "Creating project structure..."

# Backend directory
sudo -u ga mkdir -p "$WORKSPACE_DIR/backend"
cat > "$WORKSPACE_DIR/backend/main.py" << 'EOF'
"""
FastAPI Backend Service
Run with: uvicorn main:app --reload
"""
from fastapi import FastAPI

app = FastAPI()

@app.get("/")
def read_root():
    return {"message": "Backend API is running"}

@app.get("/api/health")
def health_check():
    return {"status": "healthy"}
EOF

cat > "$WORKSPACE_DIR/backend/requirements.txt" << 'EOF'
fastapi==0.104.1
uvicorn==0.24.0
EOF

# Frontend directory
sudo -u ga mkdir -p "$WORKSPACE_DIR/frontend"
cat > "$WORKSPACE_DIR/frontend/package.json" << 'EOF'
{
  "name": "frontend",
  "version": "1.0.0",
  "scripts": {
    "dev": "echo 'Frontend dev server would start here' && sleep infinity"
  }
}
EOF

cat > "$WORKSPACE_DIR/frontend/App.jsx" << 'EOF'
/**
 * React Frontend Application
 * Run with: npm run dev
 */
import React from 'react';

function App() {
  return (
    <div>
      <h1>Frontend Application</h1>
    </div>
  );
}

export default App;
EOF

# Worker directory
sudo -u ga mkdir -p "$WORKSPACE_DIR/worker"
cat > "$WORKSPACE_DIR/worker/tasks.py" << 'EOF'
"""
Celery Background Worker
Run with: celery -A tasks worker --loglevel=info
"""
from celery import Celery

app = Celery('tasks', broker='redis://localhost:6379/0')

@app.task
def process_data(data):
    """Background task to process data"""
    print(f"Processing: {data}")
    return {"status": "processed", "data": data}
EOF

cat > "$WORKSPACE_DIR/worker/requirements.txt" << 'EOF'
celery==5.3.4
redis==5.0.1
EOF

# Main README with instructions
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Microservices Project

This project contains three services that need to run concurrently during local development:

## Services

### 1. Backend API (FastAPI)