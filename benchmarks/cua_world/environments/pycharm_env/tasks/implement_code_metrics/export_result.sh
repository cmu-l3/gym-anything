#!/bin/bash
echo "=== Exporting implement_code_metrics Result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="implement_code_metrics"
PROJECT_DIR="/home/ga/PycharmProjects/code_metrics"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# 1. Take screenshot
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# 2. Run Public Tests
echo "Running pytest..."
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v --tb=short 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
ALL_TESTS_PASS=false
[ "$PYTEST_EXIT_CODE" -eq 0 ] && ALL_TESTS_PASS=true

# 3. Anti-Gaming: Run Secret Validation
# Create a temporary test file that imports the agent's code and runs it on new data
# This ensures they implemented general logic, not just hardcoded values for sample files.
SECRET_TEST_FILE="/tmp/secret_validation.py"
cat > "$SECRET_TEST_FILE" << 'PYEOF'
import sys
import os
import json

# Add project to path
sys.path.insert(0, "/home/ga/PycharmProjects/code_metrics")

try:
    from metrics.loc import count_lines
    from metrics.complexity import cyclomatic_complexity
    
    # Secret Code Sample
    secret_code = """
def secret_algo(x):
    if x > 10:
        for i in range(x):
            if i % 2 == 0:
                print(i)
    return True
"""
    # Expected: 
    # LOC total: 7, Code: 6 (lines 2,3,4,5,6,7)
    # Complexity: Base(1) + if(1) + for(1) + if(1) = 4
    
    loc = count_lines(secret_code)
    comp = cyclomatic_complexity(secret_code)
    
    # Tolerances
    loc_ok = (5 <= loc.get("code", 0) <= 7)
    
    secret_func = next((f for f in comp if f["name"] == "secret_algo"), None)
    comp_ok = False
    if secret_func:
        # Some implementations might count 'for' differently, accept 3-5
        comp_ok = (3 <= secret_func.get("complexity", 0) <= 5)
        
    print(json.dumps({"loc_ok": loc_ok, "comp_ok": comp_ok, "found_func": bool(secret_func)}))
    
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF

SECRET_RESULT=$(python3 "$SECRET_TEST_FILE" 2>/dev/null || echo '{"error": "crash"}')

# 4. Static Analysis Check
# Ensure 'ast' is used in complexity.py
AST_IMPORTED=false
if grep -q "import ast" "$PROJECT_DIR/metrics/complexity.py" 2>/dev/null; then
    AST_IMPORTED=true
fi

# 5. Check Test Integrity (Hash)
# Ensure tests/ directory hasn't been modified
TEST_HASH_VALID=true # Assuming we trust they didn't, or we could calculate md5 matches

# 6. JSON Export
cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "all_tests_pass": $ALL_TESTS_PASS,
    "secret_validation": $SECRET_RESULT,
    "ast_imported": $AST_IMPORTED,
    "pytest_output_snippet": $(echo "$PYTEST_OUTPUT" | tail -n 20 | jq -R -s '.')
}
EOF

echo "Export completed. Tests: $TESTS_PASSED passed."
cat "$RESULT_FILE"