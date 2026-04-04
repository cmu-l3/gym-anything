#!/bin/bash
set -e
echo "=== Exporting git_cherry_pick_fix result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/auth-service"
RESULT_FILE="/tmp/task_result.json"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Collect Git History of MAIN
cd "$PROJECT_DIR"
GIT_LOG_MAIN=$(git log --oneline -n 10)
CURRENT_BRANCH=$(git branch --show-current)

# 3. Read AuthUtils.java content
AUTH_UTILS_CONTENT=""
if [ -f "$PROJECT_DIR/src/main/java/com/example/auth/AuthUtils.java" ]; then
    AUTH_UTILS_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/example/auth/AuthUtils.java")
fi

# 4. Attempt Compile (to verify code validity)
BUILD_SUCCESS="false"
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile -q > /tmp/mvn_output.log 2>&1
if [ $? -eq 0 ]; then
    BUILD_SUCCESS="true"
fi

# 5. Check specific strings
HAS_FIX="false"
if echo "$AUTH_UTILS_CONTENT" | grep -q "MessageDigest.isEqual"; then
    HAS_FIX="true"
fi

HAS_WIP="false"
if echo "$AUTH_UTILS_CONTENT" | grep -q "TODO: Implement OAuth2 support"; then
    HAS_WIP="true"
fi

HAS_DEBUG="false"
if echo "$AUTH_UTILS_CONTENT" | grep -q "tempDebug"; then
    HAS_DEBUG="true"
fi

# 6. Escape content for JSON
LOG_ESCAPED=$(echo "$GIT_LOG_MAIN" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
CONTENT_ESCAPED=$(echo "$AUTH_UTILS_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

# 7. Create JSON result
cat > "$RESULT_FILE" << EOF
{
    "git_log_main": $LOG_ESCAPED,
    "current_branch": "$CURRENT_BRANCH",
    "auth_utils_content": $CONTENT_ESCAPED,
    "build_success": $BUILD_SUCCESS,
    "has_fix_code": $HAS_FIX,
    "has_wip_code": $HAS_WIP,
    "has_debug_code": $HAS_DEBUG,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 "$RESULT_FILE"

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="