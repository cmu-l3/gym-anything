#!/bin/bash
echo "=== Exporting fix_security_vulnerabilities Result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_security_vulnerabilities"
PROJECT_DIR="/home/ga/PycharmProjects/inventory_api"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true

# Run full test suite
cd "$PROJECT_DIR" || exit 1
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v --tb=short 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
ALL_TESTS_PASS=false
[ "$PYTEST_EXIT_CODE" -eq 0 ] && ALL_TESTS_PASS=true

# Check 1: JWT secret hardcoding removed
VULN1_FIXED=false
if grep -qE 'JWT_SECRET\s*=\s*os\.(environ|getenv)' "$PROJECT_DIR/app/auth.py" 2>/dev/null && \
   ! grep -q 'supersecretkey123' "$PROJECT_DIR/app/auth.py" 2>/dev/null; then
    VULN1_FIXED=true
fi
echo "$PYTEST_OUTPUT" | grep -q "test_jwt_secret_not_hardcoded PASSED" && VULN1_FIXED=true

# Check 2: SQL injection fixed (no f-string with user input in query)
VULN2_FIXED=false
if ! grep -qE "LIKE '%\{q\}%'" "$PROJECT_DIR/app/items.py" 2>/dev/null; then
    # Also check parameterized query is present
    if grep -qE "LIKE|execute" "$PROJECT_DIR/app/items.py" 2>/dev/null; then
        VULN2_FIXED=true
    fi
fi
echo "$PYTEST_OUTPUT" | grep -q "test_sql_injection_fixed PASSED" && VULN2_FIXED=true

# Check 3: IDOR fixed (ownership check in get_item)
VULN3_FIXED=false
# Look for owner_id check in the get_item function
ITEMS_CONTENT=$(cat "$PROJECT_DIR/app/items.py" 2>/dev/null || echo "")
if echo "$ITEMS_CONTENT" | grep -A20 'def get_item' | grep -q 'owner_id'; then
    VULN3_FIXED=true
fi
echo "$PYTEST_OUTPUT" | grep -q "test_idor_fixed PASSED" && VULN3_FIXED=true

# Check 4: Path traversal fixed
VULN4_FIXED=false
if grep -qE 'abspath|basename|realpath|\.\..*raise|replace.*\.\.' "$PROJECT_DIR/app/items.py" 2>/dev/null; then
    VULN4_FIXED=true
fi
echo "$PYTEST_OUTPUT" | grep -q "test_path_traversal_fixed PASSED" && VULN4_FIXED=true

# Functional tests still passing (no regression)
FUNCTIONAL_OK=false
FUNCTIONAL_PASS=true
for t in "test_login_success" "test_login_wrong_password" "test_search_own_items" "test_get_own_item" "test_get_item_not_found"; do
    if ! echo "$PYTEST_OUTPUT" | grep -q "${t} PASSED"; then
        FUNCTIONAL_PASS=false
        break
    fi
done
[ "$FUNCTIONAL_PASS" = "true" ] && FUNCTIONAL_OK=true

cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "all_tests_pass": $ALL_TESTS_PASS,
    "vuln1_hardcoded_secret_fixed": $VULN1_FIXED,
    "vuln2_sql_injection_fixed": $VULN2_FIXED,
    "vuln3_idor_fixed": $VULN3_FIXED,
    "vuln4_path_traversal_fixed": $VULN4_FIXED,
    "functional_tests_ok": $FUNCTIONAL_OK
}
EOF

echo "Pytest: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "Vuln 1 (hardcoded secret) fixed: $VULN1_FIXED"
echo "Vuln 2 (SQL injection) fixed: $VULN2_FIXED"
echo "Vuln 3 (IDOR) fixed: $VULN3_FIXED"
echo "Vuln 4 (path traversal) fixed: $VULN4_FIXED"
echo "Functional tests OK: $FUNCTIONAL_OK"
echo "=== Export Complete ==="
