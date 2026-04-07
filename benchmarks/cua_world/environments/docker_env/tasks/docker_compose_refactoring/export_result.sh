#!/bin/bash
# Export script for docker_compose_refactoring task

echo "=== Exporting Docker Compose Refactoring Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
PROJECT_DIR="/home/ga/projects/media-pipeline"
cd "$PROJECT_DIR" || echo "Project dir missing"

# 1. Check for Base File Existence
BASE_FILE_EXISTS=0
[ -f "docker-compose.base.yml" ] && BASE_FILE_EXISTS=1

# 2. Check Line Count Reduction
INITIAL_LINES=$(cat /tmp/initial_lines 2>/dev/null || echo "100")
FINAL_LINES=$(wc -l < "docker-compose.yml" 2>/dev/null || echo "100")

# 3. Check for 'extends' usage
USES_EXTENDS=0
if grep -q "extends:" "docker-compose.yml" 2>/dev/null; then
    USES_EXTENDS=1
fi

# 4. Check Effective Configuration (via docker compose config)
# This validates that the refactoring didn't break the syntax
CONFIG_VALID=0
EFFECTIVE_CONFIG=$(docker compose config 2>/dev/null || echo "")
if [ -n "$EFFECTIVE_CONFIG" ]; then
    CONFIG_VALID=1
fi

# 5. Check Runtime Status
# Are all 4 services running?
RUNNING_COUNT=$(docker compose ps --services --status running 2>/dev/null | wc -l)
ALL_SERVICES_RUNNING=0
[ "$RUNNING_COUNT" -ge 4 ] && ALL_SERVICES_RUNNING=1

# 6. Check Drift Repair (transcoder-h264 restart policy)
# We inspect the RUNNING container to see if the policy was applied
H264_RESTART_POLICY=""
if [ "$ALL_SERVICES_RUNNING" = "1" ]; then
    # Get container name for the service
    H264_CONTAINER=$(docker compose ps -q transcoder-h264 2>/dev/null)
    if [ -n "$H264_CONTAINER" ]; then
        H264_RESTART_POLICY=$(docker inspect "$H264_CONTAINER" --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null)
    fi
fi

# 7. Verify Shared Config Preservation (Check if limits are still applied)
# Pick one service to check if memory limit (512M) survived the refactor
AV1_CONTAINER=$(docker compose ps -q transcoder-av1 2>/dev/null || true)
MEMORY_LIMIT=0
if [ -n "$AV1_CONTAINER" ]; then
    MEMORY_LIMIT=$(docker inspect "$AV1_CONTAINER" --format '{{.HostConfig.Memory}}' 2>/dev/null)
fi
# 512MB = 536870912 bytes
CONFIG_PRESERVED=0
[ "$MEMORY_LIMIT" = "536870912" ] && CONFIG_PRESERVED=1

cat > /tmp/refactoring_result.json << JSONEOF
{
    "task_start": $TASK_START,
    "base_file_exists": $BASE_FILE_EXISTS,
    "initial_lines": $INITIAL_LINES,
    "final_lines": $FINAL_LINES,
    "uses_extends": $USES_EXTENDS,
    "config_valid": $CONFIG_VALID,
    "all_services_running": $ALL_SERVICES_RUNNING,
    "h264_restart_policy": "$H264_RESTART_POLICY",
    "config_preserved": $CONFIG_PRESERVED,
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF

echo "Refactoring results:"
cat /tmp/refactoring_result.json
echo "=== Export Complete ==="