#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Microservice Workspace Task ==="

PROJECTS_DIR="/home/ga/projects"
sudo -u ga mkdir -p "$PROJECTS_DIR"

# Create auth-service
echo "Creating auth-service..."
AUTH_DIR="$PROJECTS_DIR/auth-service"
sudo -u ga mkdir -p "$AUTH_DIR/tests"

cat > "$AUTH_DIR/app.py" << 'EOF'
from flask import Flask, jsonify
from shared_models import User

app = Flask(__name__)

@app.route('/auth/login', methods=['POST'])
def login():
    user = User(username="test", email="test@example.com")
    return jsonify(user.to_dict())

if __name__ == '__main__':
    app.run(port=5001)
EOF

cat > "$AUTH_DIR/requirements.txt" << 'EOF'
flask==2.3.0
shared-models==1.0.0
EOF

cat > "$AUTH_DIR/tests/test_auth.py" << 'EOF'
def test_login():
    assert True
EOF

cat > "$AUTH_DIR/README.md" << 'EOF'
# Auth Service

Authentication microservice for user login/logout.

## Endpoints
- POST /auth/login
- POST /auth/logout
EOF

# Initialize git repo
cd "$AUTH_DIR"
sudo -u ga git init
sudo -u ga git config user.name "GA User"
sudo -u ga git config user.email "ga@localhost"
sudo -u ga git add .
sudo -u ga git commit -m "Initial auth service" 2>/dev/null || true

# Create shared-models
echo "Creating shared-models..."
MODELS_DIR="$PROJECTS_DIR/shared-models"
sudo -u ga mkdir -p "$MODELS_DIR"

cat > "$MODELS_DIR/models.py" << 'EOF'
class User:
    def __init__(self, username, email):
        self.username = username
        self.email = email
    
    def to_dict(self):
        return {
            'username': self.username,
            'email': self.email
        }

class Product:
    def __init__(self, name, price):
        self.name = name
        self.price = price
    
    def to_dict(self):
        return {
            'name': self.name,
            'price': self.price
        }
EOF

cat > "$MODELS_DIR/__init__.py" << 'EOF'
from .models import User, Product
EOF

cat > "$MODELS_DIR/setup.py" << 'EOF'
from setuptools import setup, find_packages

setup(
    name='shared-models',
    version='1.0.0',
    packages=find_packages(),
    description='Shared data models for microservices'
)
EOF

cat > "$MODELS_DIR/README.md" << 'EOF'
# Shared Models

Common data models used across all microservices.

## Models
- User
- Product
EOF

# Initialize git repo
cd "$MODELS_DIR"
sudo -u ga git init
sudo -u ga git config user.name "GA User"
sudo -u ga git config user.email "ga@localhost"
sudo -u ga git add .
sudo -u ga git commit -m "Initial shared models" 2>/dev/null || true

# Create api-gateway
echo "Creating api-gateway..."
GATEWAY_DIR="$PROJECTS_DIR/api-gateway"
sudo -u ga mkdir -p "$GATEWAY_DIR/routes"

cat > "$GATEWAY_DIR/server.js" << 'EOF'
const express = require('express');
const axios = require('axios');

const app = express();
app.use(express.json());

app.post('/api/login', async (req, res) => {
    try {
        const response = await axios.post('http://localhost:5001/auth/login', req.body);
        res.json(response.data);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.listen(3000, () => {
    console.log('API Gateway running on port 3000');
});
EOF

cat > "$GATEWAY_DIR/package.json" << 'EOF'
{
  "name": "api-gateway",
  "version": "1.0.0",
  "description": "API Gateway for microservices",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.0",
    "axios": "^1.4.0"
  }
}
EOF

cat > "$GATEWAY_DIR/routes/auth.js" << 'EOF'
module.exports = {
    loginRoute: '/api/login',
    logoutRoute: '/api/logout'
};
EOF

cat > "$GATEWAY_DIR/README.md" << 'EOF'
# API Gateway

Main entry point for all microservice requests.

## Routes
- POST /api/login - Proxies to auth-service
- GET /api/health - Health check
EOF

# Initialize git repo
cd "$GATEWAY_DIR"
sudo -u ga git init
sudo -u ga git config user.name "GA User"
sudo -u ga git config user.email "ga@localhost"
sudo -u ga git add .
sudo -u ga git commit -m "Initial gateway" 2>/dev/null || true

# Set permissions
sudo chown -R ga:ga "$PROJECTS_DIR"

# Close any existing VSCode windows
echo "Closing existing VSCode instances..."
sudo -u ga pkill -f "code" || true
sleep 2

# Start VSCode with NO workspace (critical - agent must create workspace)
echo "Starting VSCode with no workspace..."
su - ga -c "DISPLAY=:1 code --new-window" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Microservice Workspace Setup Complete ==="
echo ""
echo "📁 Project Structure:"
echo "  /home/ga/projects/"
echo "  ├── auth-service/      (Python Flask authentication API)"
echo "  ├── shared-models/     (Shared data models library)"
echo "  └── api-gateway/       (Node.js API gateway)"
echo ""
echo "📝 Task Instructions:"
echo "  Create a multi-root workspace file at:"
echo "  /home/ga/projects/microservices.code-workspace"
echo ""
echo "  Method 1 (GUI):"
echo "    1. File → Add Folder to Workspace → Select 'auth-service'"
echo "    2. File → Add Folder to Workspace → Select 'shared-models'"
echo "    3. File → Add Folder to Workspace → Select 'api-gateway'"
echo "    4. File → Save Workspace As → Save to /home/ga/projects/microservices.code-workspace"
echo ""
echo "  Method 2 (Manual):"
echo "    1. Create /home/ga/projects/microservices.code-workspace"
echo "    2. Add JSON with folders array containing all three projects"
echo "    3. File → Open Workspace from File → Select microservices.code-workspace"