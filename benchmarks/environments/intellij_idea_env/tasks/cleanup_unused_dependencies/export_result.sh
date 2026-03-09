#!/bin/bash
echo "=== Exporting cleanup_unused_dependencies result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/dependency-cleanup"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Read Final pom.xml content
POM_CONTENT=""
if [ -f "$PROJECT_DIR/pom.xml" ]; then
    POM_CONTENT=$(cat "$PROJECT_DIR/pom.xml")
fi

# 2. Run Maven Compile to check if build broke
COMPILE_SUCCESS="false"
COMPILE_OUTPUT=""
if [ -f "$PROJECT_DIR/pom.xml" ]; then
    cd "$PROJECT_DIR"
    COMPILE_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile -q 2>&1)
    if [ $? -eq 0 ]; then
        COMPILE_SUCCESS="true"
    fi
fi

# 3. Run Tests
TEST_SUCCESS="false"
if [ "$COMPILE_SUCCESS" = "true" ]; then
    cd "$PROJECT_DIR"
    if JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test -q 2>/dev/null; then
        TEST_SUCCESS="true"
    fi
fi

# 4. Anti-gaming: Check file modification
FILE_MODIFIED="false"
if [ -f /tmp/initial_pom_hash.txt ]; then
    CURRENT_HASH=$(md5sum "$PROJECT_DIR/pom.xml" 2>/dev/null)
    INITIAL_HASH=$(cat /tmp/initial_pom_hash.txt 2>/dev/null)
    # Compare only the checksum part
    if [ "$(echo "$CURRENT_HASH" | awk '{print $1}')" != "$(echo "$INITIAL_HASH" | awk '{print $1}')" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 5. Check if source files were deleted (Anti-gaming)
SOURCES_INTACT="true"
REQUIRED_SOURCES=(
    "src/main/java/com/example/cleanup/App.java"
    "src/main/java/com/example/cleanup/DataProcessor.java"
    "src/main/java/com/example/cleanup/Message.java"
    "src/main/java/com/example/cleanup/StringHelper.java"
    "src/test/java/com/example/cleanup/AppTest.java"
)
for src in "${REQUIRED_SOURCES[@]}"; do
    if [ ! -s "$PROJECT_DIR/$src" ]; then
        SOURCES_INTACT="false"
        echo "Missing or empty: $src"
    fi
done

# Escape content for JSON
POM_ESCAPED=$(echo "$POM_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "pom_content": $POM_ESCAPED,
    "compile_success": $COMPILE_SUCCESS,
    "test_success": $TEST_SUCCESS,
    "pom_modified": $FILE_MODIFIED,
    "sources_intact": $SOURCES_INTACT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="