#!/bin/bash
# Setup script for docker_build_arg_optimization task

set -e
echo "=== Setting up Docker Build Arg Optimization Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Wait for Docker
if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done; return 1
    }
fi
wait_for_docker

# 2. Create Project Directory
PROJECT_DIR="/home/ga/projects/version-app"
mkdir -p "$PROJECT_DIR"

# 3. Create Application Files

# app.py
cat > "$PROJECT_DIR/app.py" << 'EOF'
import os
from flask import Flask

app = Flask(__name__)

@app.route('/')
def hello():
    # Attempt to get version from environment
    version = os.environ.get('APP_VERSION', 'None')
    return f"App Version: {version}"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

# requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
flask==2.3.3
requests==2.31.0
EOF

# Dockerfile (BROKEN & INEFFICIENT STATE)
# Problems:
# 1. ARG APP_VERSION is at the top, invalidating cache for COPY and RUN if changed
# 2. No ENV APP_VERSION=$APP_VERSION, so app.py sees None
cat > "$PROJECT_DIR/Dockerfile" << 'EOF'
FROM python:3.9-slim

WORKDIR /app

# BAD PRACTICE: ARG here invalidates the cache for subsequent layers when it changes
ARG APP_VERSION

# BAD PRACTICE: COPY . . usually happens after deps install to allow caching deps
COPY . .

# Simulating a heavy install process
RUN pip install --no-cache-dir -r requirements.txt && \
    echo "Dependencies installed."

CMD ["python", "app.py"]
EOF

# build_and_run.sh (Helper for agent)
cat > "$PROJECT_DIR/build_and_run.sh" << 'EOF'
#!/bin/bash
VERSION=${1:-1.0}
echo "Building version $VERSION..."
docker build -t version-app:$VERSION --build-arg APP_VERSION=$VERSION .

echo "Running container..."
docker rm -f version-app-test 2>/dev/null || true
docker run -d --name version-app-test -p 5000:5000 version-app:$VERSION
sleep 2

echo "Testing endpoint..."
curl -s http://localhost:5000/
echo ""
EOF

chmod +x "$PROJECT_DIR/build_and_run.sh"
chown -R ga:ga "$PROJECT_DIR"

# 4. Build the initial broken image so the agent sees the starting state
# We build with version 0.1
echo "Building initial broken image..."
su - ga -c "cd $PROJECT_DIR && ./build_and_run.sh 0.1"

# 5. Record Initial State
date +%s > /tmp/task_start_timestamp
# Save the checksum of the initial Dockerfile
md5sum "$PROJECT_DIR/Dockerfile" | awk '{print $1}' > /tmp/initial_dockerfile_md5

# 6. Setup Desktop Environment
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Launch terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/version-app && echo \"Build Optimization Task\"; echo \"Current Status: App reports Version: None\"; echo \"Goal: Fix ARG persistence and optimize cache.\"; ls -la; exec bash'" > /tmp/terminal.log 2>&1 &

# Initial screenshot
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup Complete ==="