#!/bin/bash
echo "=== Exporting Task Results ==="

PROJECT_DIR="/home/ga/projects/ci-pipeline"
cd "$PROJECT_DIR" || exit 1

# 1. Capture the docker-compose config (resolved) for static analysis
# Use 'docker compose config' to validate syntax and output resolved YAML
COMPOSE_CONFIG_JSON=$(docker compose config --format json 2>/dev/null || echo "{}")
cat "$PROJECT_DIR/docker-compose.yml" > /tmp/submitted_compose.yml

# 2. Test Dynamic Behavior
# We assume the agent might have left it running, or stopped it.
# To be sure we test the solution, we will tear down and restart cleanly.
# This ensures we are testing the CONFIGURATION, not just a lucky manual run.

echo "Restarting stack to verify determinism..."
docker compose down -v --remove-orphans >/dev/null 2>&1 || true
docker compose up -d --build > /tmp/startup.log 2>&1

# Wait for convergence (max 60s)
# We expect: db healthy, seeder exited 0, backend running
echo "Waiting for stack convergence..."
sleep 15 

# 3. Collect Container States
DB_STATE=$(docker inspect $(docker compose ps -q db) --format '{{.State.Health.Status}}' 2>/dev/null || echo "missing")
SEEDER_EXIT_CODE=$(docker inspect $(docker compose ps -q seeder 2>/dev/null) --format '{{.State.ExitCode}}' 2>/dev/null || echo "-1")
BACKEND_STATE=$(docker inspect $(docker compose ps -q backend) --format '{{.State.Status}}' 2>/dev/null || echo "missing")

# 4. Check API Health
API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/health || echo "000")
API_BODY=$(curl -s http://localhost:5000/health || echo "")

# 5. Check Timestamps for Ordering
# We want: Seeder Finish < Backend Start
SEEDER_FINISH_TS=$(docker inspect $(docker compose ps -q seeder) --format '{{.State.FinishedAt}}' 2>/dev/null || echo "")
BACKEND_START_TS=$(docker inspect $(docker compose ps -q backend) --format '{{.State.StartedAt}}' 2>/dev/null || echo "")

# Convert ISO timestamps to epoch if they exist
if [ -n "$SEEDER_FINISH_TS" ] && [ "$SEEDER_FINISH_TS" != "0001-01-01T00:00:00Z" ]; then
    SEEDER_EPOCH=$(date -d "$SEEDER_FINISH_TS" +%s 2>/dev/null || echo "0")
else
    SEEDER_EPOCH=0
fi

if [ -n "$BACKEND_START_TS" ]; then
    BACKEND_EPOCH=$(date -d "$BACKEND_START_TS" +%s 2>/dev/null || echo "0")
else
    BACKEND_EPOCH=0
fi

# 6. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 7. Write Result JSON
# Escape quotes in JSON content
SAFE_CONFIG=$(echo "$COMPOSE_CONFIG_JSON" | base64 -w 0)

cat > /tmp/task_result.json << EOF
{
    "db_health_status": "$DB_STATE",
    "seeder_exit_code": $SEEDER_EXIT_CODE,
    "backend_status": "$BACKEND_STATE",
    "api_status_code": $API_STATUS,
    "api_response": "$API_BODY",
    "seeder_finish_epoch": $SEEDER_EPOCH,
    "backend_start_epoch": $BACKEND_EPOCH,
    "compose_config_b64": "$SAFE_CONFIG"
}
EOF

# Log for debugging
echo "Exported data:"
cat /tmp/task_result.json

echo "=== Export Complete ==="