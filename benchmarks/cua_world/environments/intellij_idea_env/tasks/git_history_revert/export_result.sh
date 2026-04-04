#!/bin/bash
echo "=== Exporting git_history_revert result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/git-bisect-lab"
RESULT_JSON="/tmp/task_result.json"

# Capture final screenshot
take_screenshot /tmp/task_end.png

# --- Data Collection ---

cd "$PROJECT_DIR"

# 1. Get current git log (oneline)
GIT_LOG=$(git log --oneline -n 15)
COMMIT_COUNT=$(git rev-list --count HEAD)

# 2. Check if a revert commit exists
# Looks for "Revert" in the message and ensures it's recent (timestamp > task start)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
HAS_REVERT_COMMIT="false"
REVERT_COMMIT_HASH=""

# We check the last 3 commits for a revert message
LATEST_COMMITS=$(git log -n 3 --format="%H|%ct|%s")

while IFS= read -r line; do
    HASH=$(echo "$line" | cut -d'|' -f1)
    TS=$(echo "$line" | cut -d'|' -f2)
    MSG=$(echo "$line" | cut -d'|' -f3)
    
    # Check if message contains "Revert" and timestamp is after task start
    if [[ "$MSG" == *"Revert"* ]] || [[ "$MSG" == *"revert"* ]]; then
        if [ "$TS" -gt "$TASK_START" ]; then
            HAS_REVERT_COMMIT="true"
            REVERT_COMMIT_HASH="$HASH"
            break
        fi
    fi
done <<< "$LATEST_COMMITS"

# 3. Read MathUtils.java content
MATH_UTILS_CONTENT=""
if [ -f "src/main/java/com/example/MathUtils.java" ]; then
    MATH_UTILS_CONTENT=$(cat "src/main/java/com/example/MathUtils.java")
fi

# 4. Run tests
TEST_RESULT="unknown"
TEST_OUTPUT=""
TESTS_RUN=0
TESTS_FAILED=0

# Use mvn test
TEST_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test 2>&1)
MVN_EXIT_CODE=$?

if [ $MVN_EXIT_CODE -eq 0 ]; then
    TEST_RESULT="pass"
else
    TEST_RESULT="fail"
fi

# Parse test output for quick stats
if [[ "$TEST_OUTPUT" =~ Tests\ run:\ ([0-9]+),\ Failures:\ ([0-9]+),\ Errors:\ ([0-9]+) ]]; then
    TESTS_RUN=${BASH_REMATCH[1]}
    FAILURES=${BASH_REMATCH[2]}
    ERRORS=${BASH_REMATCH[3]}
    TESTS_FAILED=$((FAILURES + ERRORS))
fi

# 5. Check if other features (GCD/LCM) still exist (to ensure they didn't just hard reset)
HAS_GCD=$(grep -c "gcd" "src/main/java/com/example/MathUtils.java" || echo "0")
HAS_LCM=$(grep -c "lcm" "src/main/java/com/example/MathUtils.java" || echo "0")
HAS_PALINDROME=$(grep -c "isPalindrome" "src/main/java/com/example/StringUtils.java" || echo "0")

# --- JSON Export ---

# Escape strings for JSON using Python
GIT_LOG_JSON=$(echo "$GIT_LOG" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))")
MATH_CONTENT_JSON=$(echo "$MATH_UTILS_CONTENT" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))")
TEST_OUTPUT_JSON=$(echo "$TEST_OUTPUT" | tail -n 50 | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))")

cat > "$RESULT_JSON" << EOF
{
    "git_log": $GIT_LOG_JSON,
    "commit_count": $COMMIT_COUNT,
    "has_revert_commit": $HAS_REVERT_COMMIT,
    "revert_commit_hash": "$REVERT_COMMIT_HASH",
    "math_utils_content": $MATH_CONTENT_JSON,
    "test_result": "$TEST_RESULT",
    "tests_run": $TESTS_RUN,
    "tests_failed": $TESTS_FAILED,
    "test_output": $TEST_OUTPUT_JSON,
    "feature_check": {
        "has_gcd": $HAS_GCD,
        "has_lcm": $HAS_LCM,
        "has_palindrome": $HAS_PALINDROME
    },
    "timestamp": $(date +%s)
}
EOF

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "Export complete. Result saved to $RESULT_JSON"
cat "$RESULT_JSON"