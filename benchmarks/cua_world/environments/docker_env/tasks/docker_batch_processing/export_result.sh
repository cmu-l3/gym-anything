#!/bin/bash
echo "=== Exporting Docker Batch Processing Results ==="

# Define paths
CORPUS_DIR="/home/ga/projects/book-corpus"
RESULTS_DIR="$CORPUS_DIR/results"
REPORT_PATH="/home/ga/Desktop/corpus_report.json"
SCRIPT_PATH="/home/ga/Desktop/run_pipeline.sh"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Image Status
IMAGE_EXISTS="false"
IMAGE_CREATED_AT="0"
if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "book-analyzer:latest"; then
    IMAGE_EXISTS="true"
    IMAGE_CREATED_TIMESTAMP=$(docker inspect book-analyzer:latest --format '{{.Created}}' 2>/dev/null)
    IMAGE_CREATED_AT=$(date -d "$IMAGE_CREATED_TIMESTAMP" +%s 2>/dev/null || echo "0")
fi

# 2. Check Container Execution History
# Count how many containers based on this image were run
CONTAINER_COUNT=$(docker ps -a --filter ancestor=book-analyzer:latest --format '{{.ID}}' | wc -l)

# 3. Check Result Files
RESULTS_JSON="[]"
if [ -d "$RESULTS_DIR" ]; then
    # Read all json files in results dir and combine them into a JSON array string
    # We use python to safely parse and combine them to avoid bash escaping hell
    RESULTS_JSON=$(python3 -c "
import os, json
results = []
path = '$RESULTS_DIR'
if os.path.exists(path):
    for f in os.listdir(path):
        if f.endswith('.json'):
            try:
                with open(os.path.join(path, f), 'r') as file:
                    data = json.load(file)
                    data['filename'] = f  # Ensure filename is tracked
                    results.append(data)
            except:
                pass
print(json.dumps(results))
" 2>/dev/null || echo "[]")
fi

# 4. Check Merged Report
REPORT_CONTENT="{}"
REPORT_EXISTS="false"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" 2>/dev/null || echo "{}")
fi

# 5. Check Script
SCRIPT_EXISTS="false"
SCRIPT_EXECUTABLE="false"
SCRIPT_CONTENT=""
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    if [ -x "$SCRIPT_PATH" ]; then
        SCRIPT_EXECUTABLE="true"
    fi
    SCRIPT_CONTENT=$(cat "$SCRIPT_PATH" | head -n 50) # First 50 lines for inspection
fi

# 6. Capture Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 7. Construct Result JSON
cat > /tmp/batch_result.json <<EOF
{
    "task_start_time": $TASK_START,
    "image_exists": $IMAGE_EXISTS,
    "image_created_at": $IMAGE_CREATED_AT,
    "container_count": $CONTAINER_COUNT,
    "results_files_content": $RESULTS_JSON,
    "report_exists": $REPORT_EXISTS,
    "report_content": $REPORT_CONTENT,
    "script_exists": $SCRIPT_EXISTS,
    "script_executable": $SCRIPT_EXECUTABLE,
    "script_content": $(python3 -c "import json, sys; print(json.dumps(sys.stdin.read()))" <<< "$SCRIPT_CONTENT"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
cp /tmp/batch_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"