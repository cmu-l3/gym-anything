#!/bin/bash
echo "=== Setting up JaCoCo Coverage Enforcement Task ==="
source /workspace/scripts/task_utils.sh

# Copy project to home directory
echo "[SETUP] Copying transaction-service to /home/ga/..."
rm -rf /home/ga/transaction-service
cp -r /workspace/data/transaction-service /home/ga/transaction-service
chown -R ga:ga /home/ga/transaction-service

# Record start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task started at: $(cat /tmp/task_start_timestamp)"

# Baseline: count initial test files
INITIAL_TEST_COUNT=$(find /home/ga/transaction-service/src/test -name "*.java" 2>/dev/null | wc -l)
echo "$INITIAL_TEST_COUNT" > /tmp/initial_test_count
echo "Initial test file count: $INITIAL_TEST_COUNT"

# Verify JaCoCo is NOT already configured (baseline check)
INITIAL_JACOCO=$(grep -r "jacoco" /home/ga/transaction-service/pom.xml 2>/dev/null | wc -l)
echo "$INITIAL_JACOCO" > /tmp/initial_jacoco_count
echo "Initial JaCoCo config count: $INITIAL_JACOCO"

# Ensure Eclipse is running
ensure_display_ready

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
