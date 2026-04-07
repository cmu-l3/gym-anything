#!/bin/bash
# Export script for docker_ci_pipeline task

echo "=== Exporting Docker CI Pipeline Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
PROJECT_DIR="/home/ga/projects/webapp"
OUTPUT_DIR="$PROJECT_DIR/ci-output"

# 1. Check Artifacts
check_file() {
    local path="$1"
    local exists=0
    local size=0
    local modified=0
    
    if [ -f "$path" ]; then
        exists=1
        size=$(stat -c %s "$path" 2>/dev/null || echo 0)
        mtime=$(stat -c %Y "$path" 2>/dev/null || echo 0)
        if [ "$mtime" -gt "$TASK_START" ]; then
            modified=1
        fi
    fi
    echo "{\"exists\": $exists, \"size\": $size, \"modified\": $modified}"
}

LINT_STAT=$(check_file "$OUTPUT_DIR/lint-report.txt")
TEST_STAT=$(check_file "$OUTPUT_DIR/test-results.txt")
COV_STAT=$(check_file "$OUTPUT_DIR/coverage.txt")
SCAN_STAT=$(check_file "$OUTPUT_DIR/security-scan.txt")
SUMM_STAT=$(check_file "$OUTPUT_DIR/pipeline-summary.txt")

# 2. Check Scripts
PIPELINE_EXISTS=0
PIPELINE_EXECUTABLE=0
if [ -f "$PROJECT_DIR/pipeline.sh" ]; then
    PIPELINE_EXISTS=1
    if [ -x "$PROJECT_DIR/pipeline.sh" ]; then
        PIPELINE_EXECUTABLE=1
    fi
fi

DOCKERFILE_EXISTS=0
DOCKERFILE_USER_CHECK=0
if [ -f "$PROJECT_DIR/Dockerfile" ]; then
    DOCKERFILE_EXISTS=1
    if grep -q "USER " "$PROJECT_DIR/Dockerfile"; then
        DOCKERFILE_USER_CHECK=1
    fi
fi

# 3. Inspect Image
IMAGE_EXISTS=0
IMAGE_SIZE_MB=0
IMAGE_ANCESTRY_PYTHON=0

if docker inspect webapp:production >/dev/null 2>&1; then
    IMAGE_EXISTS=1
    SIZE_BYTES=$(docker inspect webapp:production --format '{{.Size}}' 2>/dev/null || echo "0")
    IMAGE_SIZE_MB=$(echo "$SIZE_BYTES" | awk '{printf "%.0f", $1/1048576}')
    
    # Check if base is python (rough check via history or config)
    # Checking Env for PYTHON_VERSION is a good heuristic for python images
    if docker inspect webapp:production --format '{{json .Config.Env}}' | grep -q "PYTHON_VERSION"; then
        IMAGE_ANCESTRY_PYTHON=1
    fi
fi

# 4. Functional Test
HEALTH_CHECK_PASSED=0
if [ "$IMAGE_EXISTS" -eq 1 ]; then
    # Stop any existing container
    docker rm -f webapp-test-export 2>/dev/null || true
    
    # Run container
    docker run -d --name webapp-test-export -p 8099:8000 webapp:production >/dev/null 2>&1
    sleep 5
    
    # Curl health
    STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8099/health || echo "000")
    if [ "$STATUS_CODE" -eq 200 ]; then
        HEALTH_CHECK_PASSED=1
    fi
    
    # Cleanup
    docker rm -f webapp-test-export >/dev/null 2>&1
fi

# 5. Content Sampling (Read first 200 chars of reports to verify they aren't empty/dummy)
# Using python to safely json-encode content
LINT_CONTENT=$(head -c 200 "$OUTPUT_DIR/lint-report.txt" 2>/dev/null | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
TEST_CONTENT=$(head -c 200 "$OUTPUT_DIR/test-results.txt" 2>/dev/null | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
SCAN_CONTENT=$(head -c 200 "$OUTPUT_DIR/security-scan.txt" 2>/dev/null | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

cat > /tmp/ci_pipeline_result.json <<EOF
{
  "task_start": $TASK_START,
  "lint_stat": $LINT_STAT,
  "test_stat": $TEST_STAT,
  "cov_stat": $COV_STAT,
  "scan_stat": $SCAN_STAT,
  "summ_stat": $SUMM_STAT,
  "pipeline_exists": $PIPELINE_EXISTS,
  "pipeline_executable": $PIPELINE_EXECUTABLE,
  "dockerfile_exists": $DOCKERFILE_EXISTS,
  "dockerfile_user_check": $DOCKERFILE_USER_CHECK,
  "image_exists": $IMAGE_EXISTS,
  "image_size_mb": $IMAGE_SIZE_MB,
  "image_ancestry_python": $IMAGE_ANCESTRY_PYTHON,
  "health_check_passed": $HEALTH_CHECK_PASSED,
  "lint_content_sample": $LINT_CONTENT,
  "test_content_sample": $TEST_CONTENT,
  "scan_content_sample": $SCAN_CONTENT,
  "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON written to /tmp/ci_pipeline_result.json"
cat /tmp/ci_pipeline_result.json
echo "=== Export Complete ==="