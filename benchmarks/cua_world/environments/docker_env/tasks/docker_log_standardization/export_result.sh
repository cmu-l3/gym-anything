#!/bin/bash
# Export script for docker_log_standardization task

echo "=== Exporting Log Standardization Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/Desktop/log_audit_report.txt"

# 1. Check Fixed Containers Configuration
# Expected: json-file, max-size=10m, max-file=3
check_container_config() {
    local name="$1"
    # Check if exists and running
    local status=$(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null || echo "missing")
    local created_ts=$(docker inspect --format '{{.Created}}' "$name" 2>/dev/null || echo "")
    local created_epoch=$(date -d "$created_ts" +%s 2>/dev/null || echo "0")
    
    # Check Log Driver Config
    local driver=$(docker inspect --format '{{.HostConfig.LogConfig.Type}}' "$name" 2>/dev/null || echo "none")
    local max_size=$(docker inspect --format '{{index .HostConfig.LogConfig.Config "max-size"}}' "$name" 2>/dev/null || echo "none")
    local max_file=$(docker inspect --format '{{index .HostConfig.LogConfig.Config "max-file"}}' "$name" 2>/dev/null || echo "none")

    # JSON Output snippet
    echo "\"$name\": {
        \"status\": \"$status\",
        \"created_epoch\": $created_epoch,
        \"driver\": \"$driver\",
        \"max_size\": \"$max_size\",
        \"max_file\": \"$max_file\"
    }"
}

# 2. Check Original Containers Status (Should be exited/missing)
check_original_status() {
    local name="$1"
    local status=$(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null || echo "missing")
    echo "\"$name\": \"$status\""
}

# 3. Check Report Content
REPORT_EXISTS=0
REPORT_HAS_ERROR_CODE=0
REPORT_SIZE=0
REPORT_MTIME=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS=1
    REPORT_SIZE=$(wc -c < "$REPORT_PATH")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if grep -q "ERR-4721" "$REPORT_PATH"; then
        REPORT_HAS_ERROR_CODE=1
    fi
fi

# Construct Result JSON
cat > /tmp/log_audit_result.json <<EOF
{
    "task_start": $TASK_START,
    "fixed_containers": {
        $(check_container_config "acme-web-fixed"),
        $(check_container_config "acme-api-fixed"),
        $(check_container_config "acme-worker-fixed"),
        $(check_container_config "acme-scheduler-fixed"),
        $(check_container_config "acme-notifier-fixed")
    },
    "original_containers": {
        $(check_original_status "acme-web"),
        $(check_original_status "acme-api"),
        $(check_original_status "acme-worker"),
        $(check_original_status "acme-scheduler"),
        $(check_original_status "acme-notifier")
    },
    "report": {
        "exists": $REPORT_EXISTS,
        "has_error_code": $REPORT_HAS_ERROR_CODE,
        "size": $REPORT_SIZE,
        "mtime": $REPORT_MTIME
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON written to /tmp/log_audit_result.json"
cat /tmp/log_audit_result.json
echo "=== Export Complete ==="