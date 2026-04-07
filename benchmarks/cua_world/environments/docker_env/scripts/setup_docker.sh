#!/bin/bash
# Docker Environment Setup Script (post_start hook)
# Creates project directories, pulls base images, sets up the working environment.

set -e

echo "=== Setting up Docker CLI Environment ==="

# Wait for Docker daemon to be ready
echo "Waiting for Docker daemon..."
for i in {1..60}; do
    if docker info > /dev/null 2>&1; then
        echo "Docker daemon ready after ${i}s"
        break
    fi
    sleep 2
done

# Enable BuildKit globally
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'DAEMONJSON'
{
  "features": {
    "buildkit": true
  },
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
DAEMONJSON
systemctl restart docker
sleep 5

# Re-wait for Docker after restart
for i in {1..30}; do
    if docker info > /dev/null 2>&1; then
        echo "Docker daemon ready"
        break
    fi
    sleep 2
done

export DOCKER_BUILDKIT=1

# Create standard project directories for the ga user
echo "Creating project directories..."
mkdir -p /home/ga/projects
mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/projects
chown -R ga:ga /home/ga/Desktop

# Copy workspace data to home directory (read-only mount → writable copy)
echo "Setting up task data in home directory..."
if [ -d /workspace/data ]; then
    cp -r /workspace/data/. /home/ga/projects/workspace-data/ 2>/dev/null || true
fi

# Load Docker base images from pre-saved workspace tarballs
# (Avoids Docker Hub rate limiting; tarballs saved via skopeo from ECR Public)
echo "Loading Docker base images from workspace tarballs..."

IMG_DIR="/workspace/data/docker_images"

load_image() {
    local tarfile="$1"
    local tag="$2"
    local tarpath="${IMG_DIR}/${tarfile}"
    if [ -f "$tarpath" ]; then
        echo "  Loading ${tag} from ${tarfile}..."
        docker load < "$tarpath" 2>&1 | grep -v "^$" || true
    else
        echo "  Tarball not found for ${tag}, trying docker pull..."
        docker pull "${tag}" 2>/dev/null || true
    fi
}

# Task 1: vulnerability remediation base images
load_image "python_3.9-slim-bullseye.tar"  "python:3.9-slim-bullseye"
load_image "node_18-bullseye-slim.tar"     "node:18-bullseye-slim"
load_image "ubuntu_20.04.tar"              "ubuntu:20.04"

# Task 2: compose application stack
load_image "postgres_14.tar"              "postgres:14"
load_image "redis_7-alpine.tar"           "redis:7-alpine"
load_image "nginx_1.24-alpine.tar"        "nginx:1.24-alpine"
load_image "python_3.11-slim.tar"         "python:3.11-slim"
load_image "node_20-slim.tar"             "node:20-slim"

# Task 3: build optimization comparison
load_image "python_3.11.tar"              "python:3.11"

# Task 4: forensics (alpine containers)
load_image "alpine_3.18.tar"              "alpine:3.18"
load_image "alpine_3.19.tar"              "alpine:3.19"

# Task 5: database migration
load_image "postgres_13.tar"              "postgres:13"
load_image "postgres_15.tar"              "postgres:15"

echo ""
echo "Loaded images:"
docker images --format "  {{.Repository}}:{{.Tag}} ({{.Size}})"

# Set up environment variables for ga user
cat >> /home/ga/.bashrc << 'BASHRC'

# Docker CLI environment settings
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

# Helpful aliases
alias dc='docker compose'
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias dlogs='docker logs --tail=50 -f'
alias dstats='docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"'
BASHRC

chown ga:ga /home/ga/.bashrc

# Open a gnome-terminal with useful context for the agent
echo "Launching terminal..."
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'echo \"Docker CLI Environment Ready\"; echo \"User: \$(whoami)\"; echo \"Docker: \$(docker --version)\"; exec bash'" > /tmp/terminal.log 2>&1 &

sleep 3

echo ""
echo "=== Docker CLI Environment Setup Complete ==="
echo ""
echo "Environment ready:"
echo "  - Docker Engine: $(docker --version)"
echo "  - Docker Compose: $(docker compose version 2>/dev/null | head -1)"
echo "  - Trivy: $(trivy --version 2>/dev/null | head -1)"
echo "  - Project directory: /home/ga/projects/"
echo ""
