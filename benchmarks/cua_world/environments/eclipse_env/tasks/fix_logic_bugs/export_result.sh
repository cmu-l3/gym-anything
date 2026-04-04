#!/bin/bash
echo "=== Exporting fix_logic_bugs result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/EcommerceBackend"
HIDDEN_SRC="/var/lib/task_hidden/tests/OrderServiceHiddenTest.java"
HIDDEN_DEST="$PROJECT_DIR/src/test/java/com/ecommerce/services/OrderServiceHiddenTest.java"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Inject Hidden Tests
echo "Injecting hidden verification tests..."
cp "$HIDDEN_SRC" "$HIDDEN_DEST"
chown ga:ga "$HIDDEN_DEST"

# 2. Run Tests via Maven (Capture output)
echo "Running verification tests..."
TEST_OUTPUT_FILE="/tmp/maven_test_output.txt"
su - ga -c "cd $PROJECT_DIR && mvn clean test" > "$TEST_OUTPUT_FILE" 2>&1 || true

# 3. Parse Results
# We check the XML reports for more reliability than parsing stdout
REPORT_DIR="$PROJECT_DIR/target/surefire-reports"
HIDDEN_REPORT="$REPORT_DIR/TEST-com.ecommerce.services.OrderServiceHiddenTest.xml"
VISIBLE_REPORT="$REPORT_DIR/TEST-com.ecommerce.services.OrderServiceTest.xml"

DISCOUNT_FIXED="false"
SHIPPING_FIXED="false"
TAX_FIXED="false"
VISIBLE_TESTS_PASS="false"
COMPILATION_SUCCESS="false"

# Check compilation (if reports exist, it compiled)
if [ -d "$REPORT_DIR" ]; then
    COMPILATION_SUCCESS="true"
fi

# Check Hidden Tests
if [ -f "$HIDDEN_REPORT" ]; then
    # Parse XML for specific test case failures
    # Logic: grep the testcase name, then look at the closing tag or failure tag
    # A passed testcase looks like: <testcase name="..." .../>
    # A failed testcase looks like: <testcase name="..."> <failure ...> </testcase>
    
    # Check Discount
    if grep -q 'name="testBulkDiscount_CalculatesCorrectly"' "$HIDDEN_REPORT"; then
        if ! grep -A 5 'name="testBulkDiscount_CalculatesCorrectly"' "$HIDDEN_REPORT" | grep -q "<failure"; then
            DISCOUNT_FIXED="true"
        fi
    fi

    # Check Shipping
    if grep -q 'name="testFreeShipping_ExactThreshold"' "$HIDDEN_REPORT"; then
        if ! grep -A 5 'name="testFreeShipping_ExactThreshold"' "$HIDDEN_REPORT" | grep -q "<failure"; then
            SHIPPING_FIXED="true"
        fi
    fi

    # Check Tax
    if grep -q 'name="testTax_NJ"' "$HIDDEN_REPORT"; then
        if ! grep -A 5 'name="testTax_NJ"' "$HIDDEN_REPORT" | grep -q "<failure"; then
            TAX_FIXED="true"
        fi
    fi
fi

# Check Visible Tests (Global Pass)
if [ -f "$VISIBLE_REPORT" ]; then
    FAILURES=$(grep 'failures="' "$VISIBLE_REPORT" | head -1 | sed 's/.*failures="\([0-9]*\)".*/\1/')
    ERRORS=$(grep 'errors="' "$VISIBLE_REPORT" | head -1 | sed 's/.*errors="\([0-9]*\)".*/\1/')
    if [ "$FAILURES" -eq "0" ] && [ "$ERRORS" -eq "0" ]; then
        VISIBLE_TESTS_PASS="true"
    fi
fi

# 4. Check Code Modification (Anti-gaming: did they actually edit the file?)
FILE_MODIFIED="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MTIME=$(stat -c %Y "$PROJECT_DIR/src/main/java/com/ecommerce/services/OrderService.java" 2>/dev/null || echo "0")

if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# 5. Clean up hidden test
rm -f "$HIDDEN_DEST"

# 6. Generate JSON Result
RESULT_JSON=$(cat << EOF
{
    "compilation_success": $COMPILATION_SUCCESS,
    "discount_fixed": $DISCOUNT_FIXED,
    "shipping_fixed": $SHIPPING_FIXED,
    "tax_fixed": $TAX_FIXED,
    "visible_tests_pass": $VISIBLE_TESTS_PASS,
    "file_modified_during_task": $FILE_MODIFIED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="