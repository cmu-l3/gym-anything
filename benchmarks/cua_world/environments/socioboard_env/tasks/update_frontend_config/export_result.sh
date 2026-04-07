#!/bin/bash
echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ENV_FILE="/opt/socioboard/socioboard-web-php/.env"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check file stats and securely copy it
if [ -f "$ENV_FILE" ]; then
    ENV_MTIME=$(stat -c %Y "$ENV_FILE" 2>/dev/null || echo "0")
    ENV_LINE_COUNT=$(wc -l < "$ENV_FILE" 2>/dev/null || echo "0")
    
    # Copy to /tmp to avoid permission issues during verification parsing
    cp "$ENV_FILE" /tmp/final_env_file.txt
    chmod 444 /tmp/final_env_file.txt
    FILE_EXISTS="true"
else
    ENV_MTIME="0"
    ENV_LINE_COUNT="0"
    FILE_EXISTS="false"
    touch /tmp/final_env_file.txt
fi

# Export metadata JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_time": $TASK_START,
    "env_mtime": $ENV_MTIME,
    "env_line_count": $ENV_LINE_COUNT,
    "file_exists": $FILE_EXISTS
}
EOF
chmod 444 /tmp/task_result.json

echo "Export complete. Results saved to /tmp/task_result.json"