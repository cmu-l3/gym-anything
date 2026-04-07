#!/bin/bash
echo "=== Exporting fix_rigid_body_physics result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/box_sim"
RESULT_FILE="/tmp/fix_physics_result.json"

# Take final screenshot
take_screenshot /tmp/fix_physics_final.png

# Run tests
echo "Running tests..."
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
ALL_TESTS_PASS=false
if [ "$PYTEST_EXIT_CODE" -eq 0 ]; then
    ALL_TESTS_PASS=true
fi

# Static Analysis for Fix Verification

# Bug 1: Integration (body.py)
# Check for use of dt in position update
BODY_PY="$PROJECT_DIR/engine/body.py"
BUG1_FIXED=false
if grep -q "position.*+.*velocity.*\*.*dt" "$BODY_PY" || \
   grep -q "position.*+=.*velocity.*\*.*dt" "$BODY_PY"; then
    BUG1_FIXED=true
fi

# Bug 2: Impulse (solver.py)
# Check for use of inv_mass in denominator
SOLVER_PY="$PROJECT_DIR/engine/solver.py"
BUG2_FIXED=false
if grep -q "inv_mass.*+.*inv_mass" "$SOLVER_PY"; then
    BUG2_FIXED=true
fi

# Bug 3: Positional Correction (solver.py)
# Check for correct subtraction/addition order
# A should be -= correction (if vector points A->B and correction aligns) or similar logic
# The bug was a.pos += corr, b.pos -= corr (pulling together)
# The fix is usually a.pos -= corr * ... b.pos += corr * ... (pushing apart)
# We check if signs are different from original buggy version.
# Original buggy: a.position = a.position + correction * a.inv_mass
#                 b.position = b.position - correction * b.inv_mass
# Correct:        a.position = a.position - correction * ...
#                 b.position = b.position + correction * ...
BUG3_FIXED=false
# We check for the pattern "a.position - correction" or "a.position -= correction"
if grep -q "a\.position.*-.*correction" "$SOLVER_PY" || \
   grep -q "a\.position.*-=.*correction" "$SOLVER_PY"; then
    # Also check B is +
    if grep -q "b\.position.*+.*correction" "$SOLVER_PY" || \
       grep -q "b\.position.*+=.*correction" "$SOLVER_PY"; then
        BUG3_FIXED=true
    fi
fi

# Fallback: if tests pass, we assume bugs are fixed even if regex misses specific syntax
if echo "$PYTEST_OUTPUT" | grep -q "test_integration_moves_correct_distance PASSED"; then
    BUG1_FIXED=true
fi
if echo "$PYTEST_OUTPUT" | grep -q "test_collision_heavy_vs_light PASSED"; then
    BUG2_FIXED=true
fi
if echo "$PYTEST_OUTPUT" | grep -q "test_positional_correction_separation PASSED"; then
    BUG3_FIXED=true
fi

# Create result JSON
cat > "$RESULT_FILE" << EOF
{
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "all_tests_pass": $ALL_TESTS_PASS,
    "bug1_fixed": $BUG1_FIXED,
    "bug2_fixed": $BUG2_FIXED,
    "bug3_fixed": $BUG3_FIXED,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"