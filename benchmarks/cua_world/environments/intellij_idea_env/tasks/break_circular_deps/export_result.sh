#!/bin/bash
echo "=== Exporting break_circular_deps result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/order-management"
MODEL_DIR="$PROJECT_DIR/src/main/java/com/example/order/model"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Run Compilation
echo "Running maven compile..."
cd "$PROJECT_DIR"
BUILD_OUTPUT=$(su - ga -c "cd $PROJECT_DIR && mvn clean compile" 2>&1)
BUILD_EXIT_CODE=$?

if [ $BUILD_EXIT_CODE -eq 0 ]; then
    BUILD_SUCCESS="true"
else
    BUILD_SUCCESS="false"
fi

# 2. Run Tests
echo "Running maven test..."
TEST_OUTPUT=$(su - ga -c "cd $PROJECT_DIR && mvn test" 2>&1)
TEST_EXIT_CODE=$?

# Parse test results
TESTS_RUN=0
TESTS_FAILED=0
TESTS_ERRORS=0

if [ -d "$PROJECT_DIR/target/surefire-reports" ]; then
    for report in "$PROJECT_DIR/target/surefire-reports"/*.xml; do
        if [ -f "$report" ]; then
            TR=$(grep -oP 'tests="\K[0-9]+' "$report" 2>/dev/null | head -1)
            TF=$(grep -oP 'failures="\K[0-9]+' "$report" 2>/dev/null | head -1)
            TE=$(grep -oP 'errors="\K[0-9]+' "$report" 2>/dev/null | head -1)
            TESTS_RUN=$((TESTS_RUN + ${TR:-0}))
            TESTS_FAILED=$((TESTS_FAILED + ${TF:-0}))
            TESTS_ERRORS=$((TESTS_ERRORS + ${TE:-0}))
        fi
    done
fi
TOTAL_FAILURES=$((TESTS_FAILED + TESTS_ERRORS))

# 3. Analyze Imports (The Core Check)
echo "Analyzing imports for circular dependencies..."
FORBIDDEN_IMPORT="com.example.order.service"
VIOLATIONS_FOUND="false"
VIOLATION_DETAILS=""

if [ -d "$MODEL_DIR" ]; then
    # Grep for forbidden imports in all model files
    # We look for "import com.example.order.service" or fully qualified usage
    GREP_RESULT=$(grep -r "$FORBIDDEN_IMPORT" "$MODEL_DIR" || true)
    
    if [ -n "$GREP_RESULT" ]; then
        VIOLATIONS_FOUND="true"
        VIOLATION_DETAILS=$(echo "$GREP_RESULT" | head -5) # Keep first 5 lines
    fi
else
    VIOLATIONS_FOUND="true"
    VIOLATION_DETAILS="Model directory not found!"
fi

# 4. Check for Specific Fixes (Optional heuristic)
ORDER_FIXED="false"
CUSTOMER_FIXED="false"

if [ -f "$MODEL_DIR/Order.java" ]; then
    if ! grep -q "DiscountService" "$MODEL_DIR/Order.java"; then
        ORDER_FIXED="true"
    fi
fi

if [ -f "$MODEL_DIR/Customer.java" ]; then
    if ! grep -q "FormattingService" "$MODEL_DIR/Customer.java"; then
        CUSTOMER_FIXED="true"
    fi
fi

# Escape output for JSON
BUILD_OUT_ESC=$(echo "$BUILD_OUTPUT" | tail -20 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
VIOLATION_ESC=$(echo "$VIOLATION_DETAILS" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Create Result JSON
RESULT_JSON=$(cat << EOF
{
    "build_success": $BUILD_SUCCESS,
    "build_output": $BUILD_OUT_ESC,
    "tests_run": $TESTS_RUN,
    "tests_failed": $TOTAL_FAILURES,
    "circular_deps_found": $VIOLATIONS_FOUND,
    "violations": $VIOLATION_ESC,
    "order_fixed": $ORDER_FIXED,
    "customer_fixed": $CUSTOMER_FIXED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="