#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Debug Docker Container Task ==="

WORKSPACE_DIR="/home/ga/workspace/flask_docker_project"
sudo -u ga mkdir -p "$WORKSPACE_DIR"/{app,.vscode}

# Ensure Docker service is running
if ! systemctl is-active --quiet docker; then
    echo "Starting Docker service..."
    systemctl start docker
    sleep 2
fi

# Stop and remove any existing container with the same name
docker stop flask_debug_app 2>/dev/null || true
docker rm flask_debug_app 2>/dev/null || true

# Create Flask application (WITHOUT debugpy initially)
cat > "$WORKSPACE_DIR/app/main.py" << 'EOF'
from flask import Flask, jsonify, request
import os

app = Flask(__name__)

@app.route('/api/calculate', methods=['POST'])
def calculate():
    data = request.get_json()
    price = data.get('price', 0)
    discount_rate = data.get('discount_rate', 0)
    
    # Bug: This calculation is wrong in certain conditions
    result = calculate_discount(price, discount_rate)
    
    return jsonify({'discounted_price': result})

def calculate_discount(price, discount_rate):
    """Calculate discounted price - HAS A BUG"""
    # Developer needs to set breakpoint here
    multiplier = 1 - (discount_rate / 100)
    discounted = price * multiplier
    
    # Bug: This environment variable check is causing issues
    if os.getenv('APPLY_TAX', 'false') == 'true':
        discounted = discounted * 1.08  # Add tax
    
    return round(discounted, 2)

if __name__ == '__main__':
    # TODO: Add debugpy initialization here
    # import debugpy
    # debugpy.listen(("0.0.0.0", 5678))
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF

# Create __init__.py
touch "$WORKSPACE_DIR/app/__init__.py"

# Create Dockerfile
cat > "$WORKSPACE_DIR/Dockerfile" << 'EOF'
FROM python:3.10-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ .

EXPOSE 5000

CMD ["python", "main.py"]
EOF

# Create docker-compose.yml (WITHOUT port 5678 exposed initially)
cat > "$WORKSPACE_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  flask_app:
    build: .
    container_name: flask_debug_app
    ports:
      - "5000:5000"
      # TODO: Add debug port mapping: "5678:5678"
    environment:
      - APPLY_TAX=true
      - FLASK_ENV=development
    volumes:
      - ./app:/app
    command: python main.py
EOF

# Create requirements.txt
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
flask==2.3.0
werkzeug==2.3.0
EOF

# Create README with instructions
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Flask Docker Debug Task

## Your Task
Configure VSCode to debug the Python Flask app running inside the Docker container.

## Current State
- Flask app is running in container `flask_debug_app` on port 5000
- debugpy is NOT installed
- Debug port 5678 is NOT exposed
- No launch.json configuration exists

## Steps to Complete

1. **Install debugpy in container**: