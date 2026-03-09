#!/bin/bash
echo "=== Setting up legacy_exception_hardening task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/legacy-service"

# Copy project from data directory
rm -rf "$PROJECT_DIR" 2>/dev/null || true
cp -r /workspace/data/legacy-service "$PROJECT_DIR"
chown -R ga:ga "$PROJECT_DIR"

# Pre-resolve Maven dependencies so IntelliJ doesn't need network
su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn -q dependency:resolve -f '$PROJECT_DIR/pom.xml'" 2>/dev/null || true

# Record checksums of test files (must not be modified)
md5sum "$PROJECT_DIR/src/test/java/com/legacy/ExceptionHandlingTest.java" \
    > /tmp/initial_test_checksum.txt 2>/dev/null

# Record initial test result (baseline failures — expects 4 of 9 tests to fail)
timeout 60 su - ga -c \
    "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test -f '$PROJECT_DIR/pom.xml' 2>&1" \
    > /tmp/initial_test_result.txt 2>&1 || true

# Record start timestamp
date +%s > /tmp/task_start_timestamp

# Open the project in IntelliJ
setup_intellij_project "$PROJECT_DIR" "legacy-service" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="
echo "Project: $PROJECT_DIR"
echo "Audit report is at: $PROJECT_DIR/AUDIT_REPORT.md"
echo "Expected: 4 of 9 tests failing initially"
