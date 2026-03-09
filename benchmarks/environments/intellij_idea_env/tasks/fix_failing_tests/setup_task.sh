#!/bin/bash
echo "=== Setting up fix_failing_tests task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/fix-failing-tests"

# Copy project from data directory
rm -rf "$PROJECT_DIR" 2>/dev/null || true
cp -r /workspace/data/fix-failing-tests "$PROJECT_DIR"
chown -R ga:ga "$PROJECT_DIR"

# Pre-resolve Maven dependencies so IntelliJ doesn't need network
cd "$PROJECT_DIR"
su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn -q dependency:resolve -f '$PROJECT_DIR/pom.xml'" 2>/dev/null || true

# Record baseline: checksum of BubbleSort.java (must not be modified)
md5sum "$PROJECT_DIR/src/main/java/com/sorts/BubbleSort.java" > /tmp/initial_bubblesort_checksum.txt 2>/dev/null

# Record initial test state: run tests to baseline the failures
INITIAL_TEST_RESULT=$(su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn -q test -f '$PROJECT_DIR/pom.xml' 2>&1" || true)
echo "$INITIAL_TEST_RESULT" > /tmp/initial_test_result.txt

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Open the project in IntelliJ
setup_intellij_project "$PROJECT_DIR" "fix-failing-tests" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="
echo "Project: $PROJECT_DIR"
echo "Initial BubbleSort.java checksum saved to /tmp/initial_bubblesort_checksum.txt"
