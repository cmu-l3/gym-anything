#!/bin/bash
echo "=== Exporting fix_genome_assembler result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_genome_assembler"
PROJECT_DIR="/home/ga/PycharmProjects/genome_assembler"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# 2. Run Test Suite
echo "Running test suite..."
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
ALL_TESTS_PASS=false
[ "$PYTEST_EXIT_CODE" -eq 0 ] && ALL_TESTS_PASS=true

# 3. Code Inspection for specific fixes

# Bug 1: io.py should yield after the loop
IO_FIXED=false
if grep -q "if header:" "$PROJECT_DIR/assembler/io.py" && \
   grep -q "yield header" "$PROJECT_DIR/assembler/io.py"; then
    # Simple heuristic: if 'yield' appears twice, or if 'if header:' block is outside loop
    # It's hard to verify strict indentation with grep, but we can check if tests pass.
    # We'll rely mainly on tests, but this flag helps debug.
    IO_FIXED=true
fi

# Bug 2: sequence.py should contain reversal slicing [::-1] or reversed()
SEQ_FIXED=false
if grep -q "\[::-1\]" "$PROJECT_DIR/assembler/sequence.py" || \
   grep -q "reversed(" "$PROJECT_DIR/assembler/sequence.py"; then
    SEQ_FIXED=true
fi

# Bug 3: overlap.py should slice the second sequence
OVERLAP_FIXED=false
if grep -q "seq2\[overlap_len:\]" "$PROJECT_DIR/assembler/overlap.py" || \
   grep -q "seq1\[:-overlap_len\]" "$PROJECT_DIR/assembler/overlap.py"; then
    OVERLAP_FIXED=true
fi

# 4. Functional Verification: Run main.py on sample data
# The correct consensus for the provided sample data (reads 1, 2, 3)
# Read 1: GAGTTTTATCGCTTCCATGACGCAGAAGTTAACACTTTCG
# Read 2:                                ACTTTCGGATATTTCTGATGAGTCGAAAAATTATCTTGAT
# Read 3:                                                            TTATCTTGATAAAGCAGGAATTACTACTGCTTGTTTA
#
# Overlap 1-2: "ACTTTCG" (len 7)
# Overlap 2-3: "TTATCTTGAT" (len 10)
#
# Consensus: GAGTTTTATCGCTTCCATGACGCAGAAGTTAACACTTTCGGATATTTCTGATGAGTCGAAAAATTATCTTGATAAAGCAGGAATTACTACTGCTTGTTTA
# Length: 100
EXPECTED_CONSENSUS="GAGTTTTATCGCTTCCATGACGCAGAAGTTAACACTTTCGGATATTTCTGATGAGTCGAAAAATTATCTTGATAAAGCAGGAATTACTACTGCTTGTTTA"
ACTUAL_CONSENSUS=$(su - ga -c "cd '$PROJECT_DIR' && python3 main.py data/phix_sample.fasta" | tail -n 1 | tr -d '\n\r')

FUNCTIONAL_SUCCESS=false
if [ "$ACTUAL_CONSENSUS" == "$EXPECTED_CONSENSUS" ]; then
    FUNCTIONAL_SUCCESS=true
fi

# 5. Create Result JSON
cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "all_tests_pass": $ALL_TESTS_PASS,
    "io_bug_fixed_heuristic": $IO_FIXED,
    "seq_bug_fixed_heuristic": $SEQ_FIXED,
    "overlap_bug_fixed_heuristic": $OVERLAP_FIXED,
    "functional_success": $FUNCTIONAL_SUCCESS,
    "actual_consensus": "$ACTUAL_CONSENSUS",
    "expected_consensus": "$EXPECTED_CONSENSUS"
}
EOF

# Handle permissions
chmod 666 "$RESULT_FILE"

echo "=== Export complete ==="
cat "$RESULT_FILE"