#!/bin/bash
set -e
echo "=== Exporting packet_parser result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/PycharmProjects/packet_parser"
RESULT_FILE="/tmp/task_result.json"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
HASH_FILE="/tmp/packet_parser_hashes.txt"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Run Tests and Capture Output
echo "Running tests..."
# We use a subshell and su to run as ga
TEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v 2>&1") || true
TEST_EXIT_CODE=$?

# 2. Check Test File Integrity
echo "Checking test file integrity..."
INTEGRITY_CHECK="true"
if [ -f "$HASH_FILE" ]; then
    # Verify hashes
    if ! sha256sum -c "$HASH_FILE" --status; then
        echo "WARNING: Test files have been modified!"
        INTEGRITY_CHECK="false"
    fi
else
    echo "WARNING: Hash file not found."
    INTEGRITY_CHECK="false"
fi

# 3. Code Content Analysis (Simple Check for hardcoding)
# We expect to see 'struct.unpack' or 'unpack' or bitwise operations
CODE_CHECK="false"
if grep -rE "struct\.unpack|unpack_from|<<|>>|&" "$PROJECT_DIR/parser/" | grep -v "__init__" > /dev/null; then
    CODE_CHECK="true"
fi

# 4. Parse Test Results
# Extract counts
TOTAL_TESTS=29
PASSED_COUNT=$(echo "$TEST_OUTPUT" | grep -oP '\d+ passed' | awk '{print $1}' || echo "0")
FAILED_COUNT=$(echo "$TEST_OUTPUT" | grep -oP '\d+ failed' | awk '{print $1}' || echo "0")

# Check individual test files passing
ETHERNET_PASS=$(echo "$TEST_OUTPUT" | grep -q "tests/test_ethernet.py.*100%" && echo "true" || echo "false")
IPV4_PASS=$(echo "$TEST_OUTPUT" | grep -q "tests/test_ipv4.py.*100%" && echo "true" || echo "false")
TCP_PASS=$(echo "$TEST_OUTPUT" | grep -q "tests/test_tcp.py.*100%" && echo "true" || echo "false")
UDP_PASS=$(echo "$TEST_OUTPUT" | grep -q "tests/test_udp.py.*100%" && echo "true" || echo "false")
PACKET_PASS=$(echo "$TEST_OUTPUT" | grep -q "tests/test_packet.py.*100%" && echo "true" || echo "false")

# 5. Timestamp Check (Files modified after start)
FILES_MODIFIED="false"
# Check if parser files are newer than start time
LATEST_MOD=$(find "$PROJECT_DIR/parser" -name "*.py" -printf "%T@\n" | sort -n | tail -1 | cut -d. -f1)
if [ -n "$LATEST_MOD" ] && [ "$LATEST_MOD" -gt "$START_TIME" ]; then
    FILES_MODIFIED="true"
fi

# 6. Create JSON Result
cat > "$RESULT_FILE" << EOF
{
    "tests_passed": $PASSED_COUNT,
    "tests_failed": $FAILED_COUNT,
    "tests_total": $TOTAL_TESTS,
    "ethernet_pass": $ETHERNET_PASS,
    "ipv4_pass": $IPV4_PASS,
    "tcp_pass": $TCP_PASS,
    "udp_pass": $UDP_PASS,
    "integration_pass": $PACKET_PASS,
    "integrity_check": $INTEGRITY_CHECK,
    "code_uses_struct_or_bits": $CODE_CHECK,
    "files_modified_during_task": $FILES_MODIFIED,
    "pytest_exit_code": $TEST_EXIT_CODE,
    "timestamp": $(date +%s)
}
EOF

# Handle permissions
chmod 666 "$RESULT_FILE"
echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="