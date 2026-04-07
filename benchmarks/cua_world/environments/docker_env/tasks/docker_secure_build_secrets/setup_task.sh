#!/bin/bash
# Setup script for docker_secure_build_secrets task

set -e
echo "=== Setting up Docker Secure Build Secrets Task ==="

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

# 1. Prepare Project Directory
PROJECT_DIR="/home/ga/projects/acme-trading-bot"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/secrets"

# 2. Create the Secret Token
# We use a specific pattern to make detection easy in verification
TOKEN_VALUE="acme_prod_8x92_secure_token_v1"
echo "$TOKEN_VALUE" > "$PROJECT_DIR/secrets/artifactory_token.txt"

# 3. Create Vulnerable Scripts and Dockerfile

# install_deps.sh (Vulnerable: expects argument)
cat > "$PROJECT_DIR/install_deps.sh" << 'EOF'
#!/bin/bash
set -e

# Simulating dependency installation that requires authentication
TOKEN="$1"
EXPECTED_TOKEN="acme_prod_8x92_secure_token_v1"

echo "Installing trading bot dependencies..."

if [ "$TOKEN" == "$EXPECTED_TOKEN" ]; then
    echo "Authentication successful with Artifactory."
    echo "Downloading proprietary algorithms..."
    sleep 1
    # Create a lock file to prove successful run
    echo "Dependencies installed successfully at $(date)" > /app/deps_installed.lock
    echo "Done."
else
    echo "ERROR: Invalid or missing Artifactory Token!"
    echo "Authentication failed."
    exit 1
fi
EOF
chmod +x "$PROJECT_DIR/install_deps.sh"

# Dockerfile (Vulnerable: uses ARG)
cat > "$PROJECT_DIR/Dockerfile" << EOF
# Using python:3.9-slim as base (pre-loaded in env)
FROM python:3.9-slim

WORKDIR /app

# VULNERABILITY: Passing secrets as build args leaks them in history
ARG ARTIFACTORY_TOKEN

COPY install_deps.sh .

# Pass the ARG to the script
RUN chmod +x install_deps.sh && ./install_deps.sh "\$ARTIFACTORY_TOKEN"

CMD ["python3", "-c", "print('Trading bot starting...')"]
EOF

# build.sh (Vulnerable: uses --build-arg)
cat > "$PROJECT_DIR/build.sh" << EOF
#!/bin/bash
# Enable BuildKit
export DOCKER_BUILDKIT=1

# Build the image using build-arg (INSECURE)
docker build -t acme-trading-bot:secure \\
  --build-arg ARTIFACTORY_TOKEN=\$(cat secrets/artifactory_token.txt) \\
  .
EOF
chmod +x "$PROJECT_DIR/build.sh"

# 4. Set Permissions
chown -R ga:ga "/home/ga/projects"

# 5. Build the initial vulnerable state (so the agent sees it's working but insecure)
echo "Building initial vulnerable image..."
su - ga -c "cd $PROJECT_DIR && ./build.sh"

# 6. Record Task Start Time
date +%s > /tmp/task_start_timestamp

# 7. Open Terminal for Agent
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/acme-trading-bot && echo \"Project: Acme Trading Bot Build\"; echo \"Security Issue: Secrets leaking in docker history\"; echo; echo \"Current build:\"; ./build.sh; echo; echo \"Check history leak:\"; echo \"docker history acme-trading-bot:secure\"; exec bash'" > /tmp/terminal.log 2>&1 &
sleep 3

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Token: $TOKEN_VALUE"
echo "Project Dir: $PROJECT_DIR"