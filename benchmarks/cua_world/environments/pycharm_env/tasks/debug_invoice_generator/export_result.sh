#!/bin/bash
echo "=== Exporting debug_invoice_generator result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/invoice_renderer"
RESULT_FILE="/tmp/task_result.json"

# Capture final state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Run Tests
echo "Running tests..."
cd "$PROJECT_DIR"
PYTEST_OUTPUT=$(python3 -m pytest tests/ -v 2>&1)
EXIT_CODE=$?

# Parse test counts
TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -oP '\d+ passed' | awk '{print $1}' || echo "0")
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -oP '\d+ failed' | awk '{print $1}' || echo "0")
TESTS_TOTAL=$(echo "$PYTEST_OUTPUT" | grep -oP 'collected \d+ items' | awk '{print $2}' || echo "0")

# 2. Check Code Fixes (Static Analysis)

# Check for Decimal import/usage in utils.py
DECIMAL_USED="false"
if grep -q "from decimal import Decimal" "$PROJECT_DIR/src/utils.py"; then
    DECIMAL_USED="true"
fi

# Check for masking logic change
# Original buggy code was just 'return cc_number'
MASKING_FIXED="false"
if ! grep -q "return cc_number" "$PROJECT_DIR/src/utils.py"; then
    # Simple check: assumes if they removed the direct return, they changed logic
    MASKING_FIXED="true"
fi

# Check for layout fix in generator.py
# Buggy: if self.y < 0
# Fixed: if self.y < self.bottom_margin (or 50)
LAYOUT_FIXED="false"
if grep -q "self.y < self.bottom_margin" "$PROJECT_DIR/src/generator.py" || \
   grep -q "self.y < 50" "$PROJECT_DIR/src/generator.py"; then
    LAYOUT_FIXED="true"
fi

# 3. Create JSON Result
cat > "$RESULT_FILE" << EOF
{
    "pytest_exit_code": $EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "total_tests": $TESTS_TOTAL,
    "decimal_used": $DECIMAL_USED,
    "masking_fixed": $MASKING_FIXED,
    "layout_fixed": $LAYOUT_FIXED,
    "timestamp": $(date +%s)
}
EOF

echo "Export complete."
cat "$RESULT_FILE"