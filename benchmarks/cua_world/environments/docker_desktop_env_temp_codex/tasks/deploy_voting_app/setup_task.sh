#!/bin/bash
# Setup script for deploy_voting_app task
# Uses the real Docker Example Voting App from dockersamples

echo "=== Setting up deploy_voting_app task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Wait for Docker Desktop and Docker daemon to be ready
echo "Waiting for Docker Desktop..."
wait_for_docker_daemon 60

# Create project directory
mkdir -p /home/ga/voting-app
cp /workspace/data/docker-compose.yml /home/ga/voting-app/
chown -R ga:ga /home/ga/voting-app

# Ensure no previous instance is running
cd /home/ga/voting-app
su - ga -c "cd /home/ga/voting-app && docker compose down -v 2>/dev/null || true"

# Record initial state
INITIAL_CONTAINER_COUNT=$(docker ps --format '{{.Names}}' 2>/dev/null | wc -l)
echo "$INITIAL_CONTAINER_COUNT" > /tmp/initial_container_count

# Record initial running containers
docker ps --format '{{.Names}}' 2>/dev/null > /tmp/initial_containers.txt

echo "Initial running containers: $INITIAL_CONTAINER_COUNT"

# Pre-pull images to make the task faster (but don't start them)
echo "Pre-pulling required images..."
su - ga -c "docker pull dockersamples/examplevotingapp_vote:latest" &
su - ga -c "docker pull dockersamples/examplevotingapp_result:latest" &
su - ga -c "docker pull dockersamples/examplevotingapp_worker:latest" &
su - ga -c "docker pull redis:alpine" &
su - ga -c "docker pull postgres:15-alpine" &
wait

echo ""
echo "=== Task setup complete ==="
echo ""
echo "Task: Deploy the Example Voting App using Docker Desktop"
echo "Project location: /home/ga/voting-app"
echo "Expected services: vote, result, worker, redis, db"
echo ""
echo "Hint: The agent should use Docker Desktop to start the docker-compose project"
echo "and verify all 5 containers are running."
