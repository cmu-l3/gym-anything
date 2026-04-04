#!/bin/bash
echo "=== Exporting analyze_stacktrace_fix_crash result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/ecommerce-legacy"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Compile project to check for syntax errors
echo "Compiling project..."
cd "$PROJECT_DIR"
COMPILE_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile 2>&1)
COMPILE_STATUS=$?

if [ $COMPILE_STATUS -eq 0 ]; then
    COMPILES="true"
else
    COMPILES="false"
fi

# 2. Inject Verification Test
# This test reproduces the crash scenario (Customer with null address)
mkdir -p "$PROJECT_DIR/src/test/java/com/ecommerce/core"
cat > "$PROJECT_DIR/src/test/java/com/ecommerce/core/VerificationTest.java" << 'TESTEOF'
package com.ecommerce.core;

import org.junit.Test;
import static org.junit.Assert.*;

public class VerificationTest {
    @Test
    public void testProcessOrderWithNullBillingAddress() {
        // Create customer with NULL billing address - this triggers the NPE in the original code
        Customer customer = new Customer("C1", "John Doe", null);
        Order order = new Order("O1", customer, 100.00);
        
        OrderProcessingService service = new OrderProcessingService();
        
        try {
            // This method calls calculateTax internally
            service.completeProcessing(order);
        } catch (NullPointerException e) {
            fail("NPE was thrown! The null billing address was not handled.");
        } catch (Exception e) {
            // Other exceptions are okay, we specifically want to avoid NPE
        }
    }
}
TESTEOF

# 3. Run the verification test
echo "Running verification test..."
TEST_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test -Dtest=VerificationTest 2>&1)
TEST_STATUS=$?

if [ $TEST_STATUS -eq 0 ]; then
    FIX_VERIFIED="true"
else
    FIX_VERIFIED="false"
fi

# 4. Check if file was modified
FILE_MODIFIED="false"
if [ -f "$PROJECT_DIR/src/main/java/com/ecommerce/core/OrderProcessingService.java" ]; then
    # Compare modification time with start time
    FILE_MTIME=$(stat -c %Y "$PROJECT_DIR/src/main/java/com/ecommerce/core/OrderProcessingService.java")
    START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$START_TIME" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Clean up injected test (optional, but good hygiene)
rm -f "$PROJECT_DIR/src/test/java/com/ecommerce/core/VerificationTest.java"

# Escape output for JSON
COMPILE_LOG_ESCAPED=$(echo "$COMPILE_OUTPUT" | tail -20 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
TEST_LOG_ESCAPED=$(echo "$TEST_OUTPUT" | tail -20 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Create JSON result
RESULT_JSON=$(cat << EOF
{
    "compiles": $COMPILES,
    "fix_verified": $FIX_VERIFIED,
    "file_modified": $FILE_MODIFIED,
    "compile_log": $COMPILE_LOG_ESCAPED,
    "test_log": $TEST_LOG_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="