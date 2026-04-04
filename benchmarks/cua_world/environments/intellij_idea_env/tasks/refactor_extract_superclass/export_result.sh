#!/bin/bash
echo "=== Exporting refactor_extract_superclass result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/banking-system"
PACKAGE_PATH="src/main/java/com/banking"

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Run Tests to verify functionality didn't break
echo "Running Maven tests..."
cd "$PROJECT_DIR"
TEST_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test -q 2>&1 || true)
if echo "$TEST_OUTPUT" | grep -q "BUILD SUCCESS"; then
    TESTS_PASSED="true"
else
    TESTS_PASSED="false"
fi

# 3. Read Source Files for Structural Verification
# We expect BankAccount.java to exist now
BANK_ACCOUNT_CONTENT=""
CHECKING_CONTENT=""
SAVINGS_CONTENT=""

if [ -f "$PROJECT_DIR/$PACKAGE_PATH/BankAccount.java" ]; then
    BANK_ACCOUNT_CONTENT=$(cat "$PROJECT_DIR/$PACKAGE_PATH/BankAccount.java")
fi

if [ -f "$PROJECT_DIR/$PACKAGE_PATH/CheckingAccount.java" ]; then
    CHECKING_CONTENT=$(cat "$PROJECT_DIR/$PACKAGE_PATH/CheckingAccount.java")
fi

if [ -f "$PROJECT_DIR/$PACKAGE_PATH/SavingsAccount.java" ]; then
    SAVINGS_CONTENT=$(cat "$PROJECT_DIR/$PACKAGE_PATH/SavingsAccount.java")
fi

# 4. Check file timestamps to ensure modification
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILES_MODIFIED="false"
CHECKING_MTIME=$(stat -c %Y "$PROJECT_DIR/$PACKAGE_PATH/CheckingAccount.java" 2>/dev/null || echo "0")
if [ "$CHECKING_MTIME" -gt "$TASK_START" ]; then
    FILES_MODIFIED="true"
fi

# 5. Prepare JSON Result
# Escape contents using Python for safety
BANK_ESC=$(echo "$BANK_ACCOUNT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
CHECKING_ESC=$(echo "$CHECKING_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
SAVINGS_ESC=$(echo "$SAVINGS_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
OUTPUT_ESC=$(echo "$TEST_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

cat > /tmp/task_result.json << EOF
{
    "tests_passed": $TESTS_PASSED,
    "files_modified": $FILES_MODIFIED,
    "bank_account_content": $BANK_ESC,
    "checking_content": $CHECKING_ESC,
    "savings_content": $SAVINGS_ESC,
    "test_output": $OUTPUT_ESC,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="