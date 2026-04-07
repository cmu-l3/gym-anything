#!/bin/bash
echo "=== Exporting fix_pharmacokinetic_solver Result ==="

# Source utilities
. /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/pk_tools"
RESULT_JSON="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Run Tests (Capture output)
echo "Running validation tests..."
# We run the actual test suite as 'ga'
PYTEST_OUT=$(su - ga -c "cd $PROJECT_DIR && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?

# Count passes/fails
PASSED_TESTS=$(echo "$PYTEST_OUT" | grep -c "PASSED")
FAILED_TESTS=$(echo "$PYTEST_OUT" | grep -c "FAILED")
TOTAL_TESTS=$((PASSED_TESTS + FAILED_TESTS))

# Check specific critical tests
KEL_TEST_PASS=$(echo "$PYTEST_OUT" | grep "test_kel_calculation" | grep -c "PASSED")
SIM_TEST_PASS=$(echo "$PYTEST_OUT" | grep "test_steady_state_accumulation" | grep -c "PASSED")
AUC_TEST_PASS=$(echo "$PYTEST_OUT" | grep "test_auc_calculation" | grep -c "PASSED")

# 2. Check Output CSV
CSV_PATH="$PROJECT_DIR/output/patient_732_sim.csv"
CSV_EXISTS="false"
CSV_VALID="false"
CSV_CONTENT=""

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    # Read first few lines for checking
    CSV_CONTENT=$(head -n 5 "$CSV_PATH" | base64 -w 0)
    
    # Basic valid check: has header and data
    if grep -q "time_hr,concentration_mg_L" "$CSV_PATH"; then
        CSV_VALID="true"
    fi
fi

# 3. Static Analysis of Fixes (Backup verification)
# Bug 1: Model.py should have division for kel
MODEL_FIXED="false"
if grep -q "np.log(2)\s*/\s*half_life" "$PROJECT_DIR/pk_tools/model.py" || \
   grep -q "0.693\s*/\s*half_life" "$PROJECT_DIR/pk_tools/model.py"; then
    MODEL_FIXED="true"
fi

# Bug 2: Simulation.py should have += or equivalent accumulation
SIM_FIXED="false"
if grep -q "current_conc\s*+=\s*dose" "$PROJECT_DIR/pk_tools/simulation.py" || \
   grep -q "current_conc\s*=\s*current_conc\s*+\s*dose" "$PROJECT_DIR/pk_tools/simulation.py"; then
    SIM_FIXED="true"
fi

# Bug 3: Analysis.py loop fix
AUC_FIXED="false"
if grep -q "range(len(time)\s*-\s*1)" "$PROJECT_DIR/pk_tools/analysis.py"; then
    AUC_FIXED="true"
fi

# 4. Create Result JSON
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "total_tests": $TOTAL_TESTS,
    "passed_tests": $PASSED_TESTS,
    "kel_test_pass": $KEL_TEST_PASS,
    "sim_test_pass": $SIM_TEST_PASS,
    "auc_test_pass": $AUC_TEST_PASS,
    "model_code_fixed": $MODEL_FIXED,
    "sim_code_fixed": $SIM_FIXED,
    "auc_code_fixed": $AUC_FIXED,
    "csv_exists": $CSV_EXISTS,
    "csv_valid": $CSV_VALID,
    "csv_head_b64": "$CSV_CONTENT",
    "ground_truth_params": $(cat /tmp/ground_truth_params.json 2>/dev/null || echo "{}")
}
EOF

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "Export complete. Result:"
cat "$RESULT_JSON"
EOF