#!/bin/bash
echo "=== Exporting setup_version_control result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/sort-algorithms"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check .git directory
GIT_INITIALIZED="false"
[ -d "$PROJECT_DIR/.git" ] && GIT_INITIALIZED="true"

# Check .gitignore
GITIGNORE_EXISTS="false"
GITIGNORE_HAS_TARGET="false"
GITIGNORE_HAS_IDEA="false"
GITIGNORE_HAS_IML="false"
GITIGNORE_HAS_CLASS="false"
if [ -f "$PROJECT_DIR/.gitignore" ]; then
    GITIGNORE_EXISTS="true"
    grep -q "target" "$PROJECT_DIR/.gitignore" && GITIGNORE_HAS_TARGET="true"
    grep -q ".idea" "$PROJECT_DIR/.gitignore" && GITIGNORE_HAS_IDEA="true"
    grep -q "*.iml\|\.iml" "$PROJECT_DIR/.gitignore" && GITIGNORE_HAS_IML="true"
    grep -q "*.class\|\.class" "$PROJECT_DIR/.gitignore" && GITIGNORE_HAS_CLASS="true"
fi
GITIGNORE_CONTENT=""
[ -f "$PROJECT_DIR/.gitignore" ] && GITIGNORE_CONTENT=$(cat "$PROJECT_DIR/.gitignore")

# Check git log (commits)
COMMIT_COUNT=0
INITIAL_COMMIT_MSG=""
FEATURE_COMMIT_MSG=""
if [ -d "$PROJECT_DIR/.git" ]; then
    COMMIT_COUNT=$(cd "$PROJECT_DIR" && git log --oneline 2>/dev/null | wc -l || echo "0")
    INITIAL_COMMIT_MSG=$(cd "$PROJECT_DIR" && git log --oneline 2>/dev/null | tail -1 || echo "")
    FEATURE_COMMIT_MSG=$(cd "$PROJECT_DIR" && git log --oneline 2>/dev/null | head -1 || echo "")
fi

# Check branches
BRANCH_LIST=""
FEATURE_BRANCH_EXISTS="false"
if [ -d "$PROJECT_DIR/.git" ]; then
    BRANCH_LIST=$(cd "$PROJECT_DIR" && git branch --list 2>/dev/null || echo "")
    echo "$BRANCH_LIST" | grep -q "feature/add-merge-sort" && FEATURE_BRANCH_EXISTS="true"
fi

# Check MergeSort.java exists
MERGESORT_EXISTS="false"
MERGESORT_COMPILES="false"
MERGESORT_FILE="$PROJECT_DIR/src/main/java/com/sorts/MergeSort.java"
[ -f "$MERGESORT_FILE" ] && MERGESORT_EXISTS="true"

# Check test file exists and count test methods
MERGESORT_TEST_EXISTS="false"
MERGESORT_TEST_COUNT=0
MERGESORT_TEST_FILE="$PROJECT_DIR/src/test/java/com/sorts/MergeSortTest.java"
if [ -f "$MERGESORT_TEST_FILE" ]; then
    MERGESORT_TEST_EXISTS="true"
    MERGESORT_TEST_COUNT=$(grep -c "@Test" "$MERGESORT_TEST_FILE" 2>/dev/null || echo "0")
fi

# Try to compile to verify MergeSort.java is valid
if [ "$MERGESORT_EXISTS" = "true" ]; then
    BUILD_OUTPUT=$(su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn -q compile -f '$PROJECT_DIR/pom.xml' 2>&1" && echo "BUILD_OK" || echo "BUILD_FAIL")
    [ "$BUILD_OUTPUT" = "BUILD_OK" ] && MERGESORT_COMPILES="true"
fi

# JSON-escape strings
GITIGNORE_ESCAPED=$(echo "$GITIGNORE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
BRANCH_ESCAPED=$(echo "$BRANCH_LIST" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
INIT_MSG_ESCAPED=$(echo "$INITIAL_COMMIT_MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

RESULT_JSON=$(cat << EOF
{
    "git_initialized": $GIT_INITIALIZED,
    "gitignore_exists": $GITIGNORE_EXISTS,
    "gitignore_has_target": $GITIGNORE_HAS_TARGET,
    "gitignore_has_idea": $GITIGNORE_HAS_IDEA,
    "gitignore_has_iml": $GITIGNORE_HAS_IML,
    "gitignore_has_class": $GITIGNORE_HAS_CLASS,
    "gitignore_content": $GITIGNORE_ESCAPED,
    "commit_count": $COMMIT_COUNT,
    "initial_commit_message": $INIT_MSG_ESCAPED,
    "feature_branch_exists": $FEATURE_BRANCH_EXISTS,
    "branch_list": $BRANCH_ESCAPED,
    "mergesort_exists": $MERGESORT_EXISTS,
    "mergesort_compiles": $MERGESORT_COMPILES,
    "mergesort_test_exists": $MERGESORT_TEST_EXISTS,
    "mergesort_test_count": $MERGESORT_TEST_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "git_initialized=$GIT_INITIALIZED commits=$COMMIT_COUNT feature_branch=$FEATURE_BRANCH_EXISTS mergesort=$MERGESORT_EXISTS"
echo "=== Export complete ==="
