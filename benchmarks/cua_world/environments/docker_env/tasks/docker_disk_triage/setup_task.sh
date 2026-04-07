#!/bin/bash
set -e
echo "=== Setting up Docker Disk Triage Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback for wait_for_docker if not sourced
if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done
        return 1
    }
fi

wait_for_docker

# Record start time
date +%s > /tmp/task_start_time.txt

# Clean slate
echo "Cleaning environment..."
docker rm -f $(docker ps -aq) 2>/dev/null || true
docker volume prune -f 2>/dev/null || true

# 1. Setup Protected Production Environment
echo "Setting up production containers..."

# DB with named volume
docker volume create acme-pgdata
docker run -d --name acme-prod-db \
    -v acme-pgdata:/var/lib/postgresql/data \
    -e POSTGRES_PASSWORD=password \
    postgres:14

# API linked to DB
docker run -d --name acme-prod-api \
    --link acme-prod-db:db \
    python:3.11-slim \
    sh -c "while true; do sleep 3600; done"

# Web linked to API
docker run -d --name acme-prod-web \
    --link acme-prod-api:api \
    nginx:1.24-alpine

# 2. Setup Protected Debug Container (Stopped but Labeled)
echo "Setting up debug container..."
docker run -d --name acme-debug-snapshot \
    --label preserve=true \
    alpine:3.18 \
    sh -c "echo 'Debug data' > /tmp/debug.log; sleep 5"
# Wait for it to stop naturally or stop it
docker stop acme-debug-snapshot 2>/dev/null || true

# 3. Generate "Trash" - Stopped Containers
echo "Creating trash containers..."
for i in {1..4}; do
    docker run -d --name "acme-failed-build-$i" alpine:3.18 sh -c "exit 1"
done

docker run -d --name acme-old-migration postgres:14 sh -c "echo 'Migrating... done'; exit 0"
docker run -d --name acme-test-runner-old node:20-slim sh -c "echo 'Tests failed'; exit 1"

# 4. Generate "Trash" - Orphaned Volumes
echo "Creating orphaned volumes..."
create_orphan_vol() {
    local vol="$1"
    docker volume create "$vol"
    # Populate it so it's not empty (simulating real usage)
    docker run --rm -v "$vol":/data alpine:3.18 sh -c "echo 'stale data' > /data/dump.rdb"
}

create_orphan_vol "acme-redis-data"
create_orphan_vol "acme-old-uploads"
create_orphan_vol "acme-test-fixtures"
create_orphan_vol "acme-build-cache-vol"

# 5. Generate Dangling Images
echo "Creating dangling images..."
# Create a dummy dockerfile context
mkdir -p /tmp/build_trash
cat > /tmp/build_trash/Dockerfile <<EOF
FROM alpine:3.18
ARG RANDOM
RUN echo "Layer \$RANDOM" > /layer.txt
EOF

# Build 3 times with different ARGs to create separate image layers
for i in {1..3}; do
    docker build --build-arg RANDOM=$RANDOM -t "temp-image:$i" /tmp/build_trash
done

# Now remove tags to make them dangling (but keep the layers)
docker rmi "temp-image:1" "temp-image:2" "temp-image:3" || true

# Setup Directories
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/projects/maintenance
chown -R ga:ga /home/ga/Desktop /home/ga/projects

# Open terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'echo \"Docker Disk Triage Task\"; echo \"Warning: Disk usage high.\"; echo \"Please cleanup unused resources but preserve production and labeled debug containers.\"; echo; docker system df; exec bash'" > /tmp/terminal.log 2>&1 &
sleep 2

# Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="