#!/bin/bash
echo "=== Exporting fix_classroom_autograder results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/autograder"
RESULT_FILE="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Run Tests and capture output
echo "Running tests..."
cd "$PROJECT_DIR"
PYTEST_OUTPUT=$(python3 -m pytest tests/ -v 2>&1)
PYTEST_EXIT_CODE=$?

# Count passes/fails
TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || echo "0")
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || echo "0")
TESTS_TOTAL=$((TESTS_PASSED + TESTS_FAILED))
ALL_TESTS_PASS=$([ "$PYTEST_EXIT_CODE" -eq 0 ] && echo "true" || echo "false")

# 2. Check source code for specific fixes (Static Analysis)

# Bug 1: Scorer - Linear penalty
# Should see something like: 1 - penalty_rate * days_late
# Should NOT see: ** days_late
BUG1_FIXED="false"
SCORER_CONTENT=$(cat "$PROJECT_DIR/grader/scorer.py" 2>/dev/null)
if echo "$SCORER_CONTENT" | grep -q "\*.*days_late" && ! echo "$SCORER_CONTENT" | grep -q "\*\*.*days_late"; then
    BUG1_FIXED="true"
fi

# Bug 2: Grades - Inclusive boundary
# Should see: >= 90
# Should NOT see: > 90 (without =)
BUG2_FIXED="false"
GRADES_CONTENT=$(cat "$PROJECT_DIR/grader/grades.py" 2>/dev/null)
if echo "$GRADES_CONTENT" | grep -q ">="; then
    BUG2_FIXED="true"
fi

# Bug 3: Grades - Weighted Average Denominator
# Should normalize by weights of present keys, not all weights.
# Simple heuristic: Look for iteration over keys or filtering of weights
BUG3_FIXED="false"
# If the loop adds to total_weight inside the if check, or calculates a partial sum
if echo "$GRADES_CONTENT" | grep -q "total_weight.*+=" || echo "$GRADES_CONTENT" | grep -q "sum(.*if.*)"; then
     BUG3_FIXED="true"
fi
# Alternative check: specific test pass is a strong indicator

# Bug 4: Export - Column Order
# Should write [student_id, name, ...] or dict writer
BUG4_FIXED="false"
EXPORT_CONTENT=$(cat "$PROJECT_DIR/grader/export.py" 2>/dev/null)
# Check if student_id comes before name in the list/tuple
if echo "$EXPORT_CONTENT" | grep -q "student\['student_id'\].*student\['name'\]"; then
    BUG4_FIXED="true"
fi

# 3. Anti-Gaming: Check if tests were modified
TESTS_MODIFIED="false"
CURRENT_CHECKSUM=$(find "$PROJECT_DIR/tests" -type f -exec md5sum {} + | sort)
ORIGINAL_CHECKSUM=$(cat /tmp/tests_checksum.md5 2>/dev/null)

if [ "$CURRENT_CHECKSUM" != "$ORIGINAL_CHECKSUM" ]; then
    TESTS_MODIFIED="true"
fi

# 4. Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "all_tests_pass": $ALL_TESTS_PASS,
    "bug1_static_fix": $BUG1_FIXED,
    "bug2_static_fix": $BUG2_FIXED,
    "bug3_static_fix": $BUG3_FIXED,
    "bug4_static_fix": $BUG4_FIXED,
    "tests_modified": $TESTS_MODIFIED,
    "pytest_output_sample": "$(echo "$PYTEST_OUTPUT" | head -n 20 | sed 's/"/\\"/g')"
}
EOF

# Save result safely
rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to $RESULT_FILE"