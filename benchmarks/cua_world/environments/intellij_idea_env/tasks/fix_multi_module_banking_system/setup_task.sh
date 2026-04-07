#!/bin/bash
echo "=== Setting up fix_multi_module_banking_system task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/bank-ledger-system"

# Copy project from data directory
rm -rf "$PROJECT_DIR" 2>/dev/null || true
cp -r /workspace/data/bank-ledger-system "$PROJECT_DIR"
chown -R ga:ga "$PROJECT_DIR"

# Pre-cache JUnit 4.12 and hamcrest in local Maven repo.
# The project's POM has a version mismatch bug (Bug 1) so normal
# dependency resolution will fail — fetch the test deps directly.
su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    mvn dependency:get -Dartifact=junit:junit:4.12 -Dtransitive=true -q" 2>/dev/null || true
su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    mvn dependency:get -Dartifact=org.hamcrest:hamcrest-core:1.3 -q" 2>/dev/null || true

# Also try resolving from the project (will fail due to Bug 1, but || true handles it)
su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    mvn -q dependency:resolve -f '$PROJECT_DIR/pom.xml'" 2>/dev/null || true

# Record checksums of test files (must not be modified)
md5sum "$PROJECT_DIR/bank-commons/src/test/java/com/bank/commons/CommonsTest.java" \
    > /tmp/initial_test_checksums.txt 2>/dev/null
md5sum "$PROJECT_DIR/bank-ledger/src/test/java/com/bank/ledger/LedgerTest.java" \
    >> /tmp/initial_test_checksums.txt 2>/dev/null
md5sum "$PROJECT_DIR/bank-processing/src/test/java/com/bank/processing/ProcessingTest.java" \
    >> /tmp/initial_test_checksums.txt 2>/dev/null

# Record initial build result (will fail due to Bug 1 — expected)
timeout 60 su - ga -c \
    "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile -f '$PROJECT_DIR/pom.xml' 2>&1" \
    > /tmp/initial_build_result.txt 2>&1 || true

# Delete stale outputs BEFORE recording timestamp
rm -f /tmp/task_result.json 2>/dev/null || true

# Record start timestamp
date +%s > /tmp/task_start_timestamp

# Open the project in IntelliJ
setup_intellij_project "$PROJECT_DIR" "bank-ledger-system" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="
echo "Project: $PROJECT_DIR"
echo "Multi-module project with 3 modules: bank-commons, bank-ledger, bank-processing"
echo "Expected: project fails to compile initially (POM version mismatch)"
echo "After compilation fix, 12 of 18 tests will fail"
