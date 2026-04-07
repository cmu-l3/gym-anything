#!/bin/bash
set -euo pipefail

echo "=== Exporting migrate_log_to_git_backup task results ==="

export DISPLAY="${DISPLAY:-:1}"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_BASE_DIR="/home/ga/Documents/SubsurfaceBackup"
TARGET_GIT_DIR="$TARGET_BASE_DIR/dives.git"

BASE_DIR_EXISTS="false"
GIT_DIR_EXISTS="false"
GIT_VALID="false"
COMMIT_COUNT="0"
LATEST_COMMIT_TIME="0"

# Check if base backup dir exists
if [ -d "$TARGET_BASE_DIR" ]; then
    BASE_DIR_EXISTS="true"
fi

# Check if target git dir exists
if [ -d "$TARGET_GIT_DIR" ]; then
    GIT_DIR_EXISTS="true"
    
    # Subsurface git saves can be bare or standard. Find the actual git dir.
    ACTUAL_GIT_DIR=""
    if [ -d "$TARGET_GIT_DIR/.git" ]; then
        ACTUAL_GIT_DIR="$TARGET_GIT_DIR/.git"
    elif [ -d "$TARGET_GIT_DIR/objects" ] && [ -f "$TARGET_GIT_DIR/HEAD" ]; then
        ACTUAL_GIT_DIR="$TARGET_GIT_DIR"
    fi
    
    # Validate Git repo
    if [ -n "$ACTUAL_GIT_DIR" ]; then
        if git --git-dir="$ACTUAL_GIT_DIR" rev-parse HEAD >/dev/null 2>&1; then
            GIT_VALID="true"
            COMMIT_COUNT=$(git --git-dir="$ACTUAL_GIT_DIR" rev-list --all --count 2>/dev/null || echo "0")
            LATEST_COMMIT_TIME=$(git --git-dir="$ACTUAL_GIT_DIR" log -1 --format=%ct 2>/dev/null || echo "0")
        fi
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "base_dir_exists": $BASE_DIR_EXISTS,
    "git_dir_exists": $GIT_DIR_EXISTS,
    "git_valid": $GIT_VALID,
    "commit_count": $COMMIT_COUNT,
    "latest_commit_time": $LATEST_COMMIT_TIME,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="