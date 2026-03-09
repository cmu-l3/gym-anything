#!/bin/bash
echo "=== Setting up debug_logic_error task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/debug-logic-error"

# Copy project from data directory
rm -rf "$PROJECT_DIR" 2>/dev/null || true
cp -r /workspace/data/debug-logic-error "$PROJECT_DIR"
chown -R ga:ga "$PROJECT_DIR"

# Pre-resolve Maven dependencies
cd "$PROJECT_DIR"
su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn -q dependency:resolve -f '$PROJECT_DIR/pom.xml'" 2>/dev/null || true

# Record baseline: checksum of BinarySearchTest.java (must not be modified)
md5sum "$PROJECT_DIR/src/test/java/com/search/BinarySearchTest.java" > /tmp/initial_test_checksum.txt 2>/dev/null

# Record initial test failures count (should show 4 failing)
INITIAL_TEST_OUTPUT=$(su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn -q test -f '$PROJECT_DIR/pom.xml' 2>&1" || true)
INITIAL_FAIL_COUNT=$(echo "$INITIAL_TEST_OUTPUT" | grep -c "FAIL\|FAILURE\|Failures: [^0]\|Tests in error" || echo "0")
echo "$INITIAL_FAIL_COUNT" > /tmp/initial_failure_count.txt
echo "$INITIAL_TEST_OUTPUT" >> /tmp/initial_test_result.txt

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Open the project in IntelliJ
setup_intellij_project "$PROJECT_DIR" "debug-logic-error" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="
echo "Project: $PROJECT_DIR"
echo "Initial failure count: $INITIAL_FAIL_COUNT"
