#!/bin/bash
# Setup script for docker_ci_pipeline task

set -e
echo "=== Setting up Docker CI Pipeline Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done; return 1
    }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

wait_for_docker

# Cleanup previous run
PROJECT_DIR="/home/ga/projects/webapp"
rm -rf "$PROJECT_DIR"
docker rmi -f webapp:production webapp:candidate 2>/dev/null || true

# Create project structure
mkdir -p "$PROJECT_DIR/app"
mkdir -p "$PROJECT_DIR/tests"
mkdir -p "$PROJECT_DIR/ci-output"

# 1. Application Code
cat > "$PROJECT_DIR/app/__init__.py" << 'EOF'
# Init
EOF

cat > "$PROJECT_DIR/app/models.py" << 'EOF'
class ItemModel:
    def __init__(self):
        self.items = []

    def add_item(self, name):
        item = {"id": len(self.items) + 1, "name": name}
        self.items.append(item)
        return item

    def get_all(self):
        return self.items
EOF

cat > "$PROJECT_DIR/app/routes.py" << 'EOF'
from flask import Blueprint, jsonify, request
from app.models import ItemModel

api = Blueprint('api', __name__)
items_db = ItemModel()

@api.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy"}), 200

@api.route('/api/items', methods=['GET'])
def get_items():
    return jsonify(items_db.get_all()), 200

@api.route('/api/items', methods=['POST'])
def add_item():
    data = request.get_json()
    if not data or 'name' not in data:
        return jsonify({"error": "Bad Request"}), 400
    item = items_db.add_item(data['name'])
    return jsonify(item), 201
EOF

cat > "$PROJECT_DIR/app/main.py" << 'EOF'
from flask import Flask
from app.routes import api

def create_app():
    app = Flask(__name__)
    app.register_blueprint(api)
    return app

app = create_app()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
EOF

cat > "$PROJECT_DIR/wsgi.py" << 'EOF'
from app.main import app

if __name__ == "__main__":
    app.run()
EOF

# 2. Test Code
cat > "$PROJECT_DIR/tests/__init__.py" << 'EOF'
# Init tests
EOF

cat > "$PROJECT_DIR/tests/test_models.py" << 'EOF'
import pytest
from app.models import ItemModel

def test_add_item():
    model = ItemModel()
    item = model.add_item("Test Item")
    assert item['name'] == "Test Item"
    assert item['id'] == 1
    assert len(model.items) == 1
EOF

cat > "$PROJECT_DIR/tests/test_routes.py" << 'EOF'
import pytest
from app.main import create_app

@pytest.fixture
def client():
    app = create_app()
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

def test_health(client):
    rv = client.get('/health')
    assert rv.status_code == 200
    assert rv.json == {"status": "healthy"}

def test_create_item(client):
    rv = client.post('/api/items', json={"name": "Widget"})
    assert rv.status_code == 201
    assert rv.json['name'] == "Widget"

def test_get_items(client):
    client.post('/api/items', json={"name": "Widget"})
    rv = client.get('/api/items')
    assert rv.status_code == 200
    assert len(rv.json) >= 1
EOF

# 3. Dependencies
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
flask==3.0.0
gunicorn==21.2.0
EOF

cat > "$PROJECT_DIR/requirements-dev.txt" << 'EOF'
pytest==7.4.3
pytest-cov==4.1.0
flake8==6.1.0
bandit==1.7.5
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Pre-pull base images to save time and ensure offline capability if cached
docker pull python:3.11-slim >/dev/null 2>&1 || true

# Record start time
date +%s > /tmp/task_start_timestamp

# Ensure Desktop exists
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Launch terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/webapp && echo \"Docker CI Pipeline Task Ready\"; echo \"Project at: ~/projects/webapp/\"; echo \"Goal: Create Dockerfile and pipeline.sh\"; exec bash'" > /tmp/terminal.log 2>&1 &
sleep 3

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Project created at $PROJECT_DIR"