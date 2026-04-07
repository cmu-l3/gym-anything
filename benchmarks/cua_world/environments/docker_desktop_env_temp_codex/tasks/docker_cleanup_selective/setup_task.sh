#!/bin/bash
# Setup script for docker_cleanup_selective task

echo "=== Setting up Docker Selective Cleanup Task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Docker
echo "Waiting for Docker daemon..."
wait_for_docker_daemon 60

# 2. Clean slate (in case of previous runs)
echo "Cleaning previous state..."
docker stop $(docker ps -aq) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true
docker network prune -f 2>/dev/null || true
docker volume prune -f 2>/dev/null || true
# Prune dangling images
docker image prune -f 2>/dev/null || true

# 3. Create Networks
echo "Creating networks..."
docker network create prod-net
docker network create deprecated-frontend
docker network create old-backend-net

# 4. Create Volumes
echo "Creating volumes..."
docker volume create persistent-config
# Add some dummy data to config so it looks real
docker run --rm -v persistent-config:/data alpine sh -c "echo 'prod_mode=true' > /data/config.ini"

docker volume create old-test-data
docker volume create build-cache-vol
docker volume create tmp-upload-vol

# 5. Create Running Production Containers
echo "Starting production containers..."
# prod-web (nginx)
docker run -d --name prod-web --network prod-net -p 8080:80 nginx:alpine
# prod-cache (redis)
docker run -d --name prod-cache --network prod-net redis:alpine
# prod-api (simulated with python simple http)
docker run -d --name prod-api --network prod-net python:3.11-slim python -m http.server 8000

# 6. Create Containers to Remove (Stopped)
echo "Creating trash containers..."
docker run --name old-dev-server alpine echo "server stopped"
docker run --name test-runner-0412 alpine echo "tests failed"
docker run --name failed-build-temp alpine echo "build error 127"
docker run --name expired-worker alpine echo "job complete"

# 7. Create Container to Keep (Stopped)
echo "Creating preserved stopped container..."
docker run --name staging-db-snapshot alpine echo "snapshot taken 2023-10-10"

# 8. Create Dangling Images
echo "Creating dangling images..."
# Method: Build an image tagged 'temp', then rebuild 'temp' so the old one becomes dangling
mkdir -p /tmp/build_context

# Dangling image 1
echo "FROM alpine:latest" > /tmp/build_context/Dockerfile
echo "RUN echo 'version 1' > /v1" >> /tmp/build_context/Dockerfile
docker build -t temp-image:latest /tmp/build_context

# Overwrite it (making version 1 dangling)
echo "FROM alpine:latest" > /tmp/build_context/Dockerfile
echo "RUN echo 'version 2' > /v2" >> /tmp/build_context/Dockerfile
docker build -t temp-image:latest /tmp/build_context

# Dangling image 2
echo "FROM busybox:latest" > /tmp/build_context/Dockerfile
echo "RUN echo 'artifact A' > /a" >> /tmp/build_context/Dockerfile
docker build -t temp-artifact:latest /tmp/build_context

# Overwrite it
echo "FROM busybox:latest" > /tmp/build_context/Dockerfile
echo "RUN echo 'artifact B' > /b" >> /tmp/build_context/Dockerfile
docker build -t temp-artifact:latest /tmp/build_context

# Remove the tags so we just have dangling images left (optional, but cleaner for the scenario)
docker rmi temp-image:latest
docker rmi temp-artifact:latest

# 9. Final Setup Steps
# Record initial state for verifier
echo "Recording initial state..."
get_container_count "all" > /tmp/initial_container_total
get_container_count "running" > /tmp/initial_container_running
docker images -f "dangling=true" -q | wc -l > /tmp/initial_dangling_count
docker volume ls -q | wc -l > /tmp/initial_volume_count
docker network ls -q | wc -l > /tmp/initial_network_count

# Setup workspace
date +%s > /tmp/task_start_time

# Focus Docker Desktop
focus_docker_desktop

# Take screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "State prepared:"
echo "- 3 Running Prod Containers (Keep)"
echo "- 1 Stopped Snapshot Container (Keep)"
echo "- 4 Trash Containers (Remove)"
echo "- ~2 Dangling Images (Remove)"
echo "- 1 Config Volume (Keep)"
echo "- 3 Trash Volumes (Remove)"
echo "- 2 Trash Networks (Remove)"