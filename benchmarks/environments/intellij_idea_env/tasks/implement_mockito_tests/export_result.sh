#!/bin/bash
echo "=== Exporting implement_mockito_tests result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/payment-system"
TEST_FILE="$PROJECT_DIR/src/test/java/com/payment/PaymentServiceTest.java"
SOURCE_FILE="$PROJECT_DIR/src/main/java/com/payment/PaymentService.java"
POM_FILE="$PROJECT_DIR/pom.xml"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ==============================================================================
# 1. Check File Existence
# ==============================================================================
TEST_EXISTS="false"
if [ -f "$TEST_FILE" ]; then TEST_EXISTS="true"; fi

# Check creation time to ensure anti-gaming
TEST_CREATED_DURING_TASK="false"
if [ "$TEST_EXISTS" = "true" ]; then
    FILE_CTIME=$(stat -c %Y "$TEST_FILE")
    if [ "$FILE_CTIME" -ge "$TASK_START" ]; then
        TEST_CREATED_DURING_TASK="true"
    fi
fi

# ==============================================================================
# 2. Check Dependencies (Static Analysis)
# ==============================================================================
HAS_JUNIT="false"
HAS_MOCKITO="false"
POM_CONTENT=""

if [ -f "$POM_FILE" ]; then
    POM_CONTENT=$(cat "$POM_FILE")
    if echo "$POM_CONTENT" | grep -q "junit-jupiter"; then HAS_JUNIT="true"; fi
    if echo "$POM_CONTENT" | grep -q "mockito-core"; then HAS_MOCKITO="true"; fi
fi

# ==============================================================================
# 3. Verify Tests (Mutation Testing Logic)
# ==============================================================================
# We run this INSIDE the container to leverage the environment's Maven
# We output a JSON structure summarizing the mutation results

# Helper to run tests and return status (0=pass, 1=fail)
run_tests() {
    cd "$PROJECT_DIR"
    # Use quiet mode, redirect output
    if JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test -Dsurefire.failIfNoSpecifiedTests=false -q > /dev/null 2>&1; then
        return 0 # Pass
    else
        return 1 # Fail
    fi
}

BASELINE_PASS="false"
MUTANT_A_CAUGHT="false" # No Save
MUTANT_B_CAUGHT="false" # Ignore Result
MUTANT_C_CAUGHT="false" # Wrong Status

# Backup original source
cp "$SOURCE_FILE" "${SOURCE_FILE}.bak"

echo "Running baseline tests..."
if run_tests; then
    BASELINE_PASS="true"
    
    # Only run mutations if baseline passes
    
    # --- Mutant A: Comment out repository.save() ---
    echo "Injecting Mutant A (No Save)..."
    sed -i 's/repository.save(txn);/\/\/ repository.save(txn);/g' "$SOURCE_FILE"
    if ! run_tests; then
        MUTANT_A_CAUGHT="true"
        echo "Mutant A caught!"
    else
        echo "Mutant A NOT caught."
    fi
    # Restore
    cp "${SOURCE_FILE}.bak" "$SOURCE_FILE"
    
    # --- Mutant B: Ignore charge result (always success) ---
    echo "Injecting Mutant B (Ignore Charge Result)..."
    # Replace the charge call line with hardcoded true, but keep the call to avoid unused mocks if verify is strict?
    # Actually, easiest is to force 'success' to true in the if condition logic
    # Original: boolean success = processor.charge(...)
    # Mutant: boolean success = processor.charge(...); success = true; 
    sed -i '/boolean success = processor.charge/a \            success = true;' "$SOURCE_FILE"
    if ! run_tests; then
        MUTANT_B_CAUGHT="true"
        echo "Mutant B caught!"
    else
        echo "Mutant B NOT caught."
    fi
    # Restore
    cp "${SOURCE_FILE}.bak" "$SOURCE_FILE"
    
    # --- Mutant C: Wrong Status (SUCCESS -> DECLINED) ---
    echo "Injecting Mutant C (Wrong Status)..."
    sed -i 's/TransactionStatus.SUCCESS/TransactionStatus.DECLINED/g' "$SOURCE_FILE"
    if ! run_tests; then
        MUTANT_C_CAUGHT="true"
        echo "Mutant C caught!"
    else
        echo "Mutant C NOT caught."
    fi
    # Restore
    cp "${SOURCE_FILE}.bak" "$SOURCE_FILE"

else
    echo "Baseline tests failed. Skipping mutation testing."
fi

# Clean up backup
rm -f "${SOURCE_FILE}.bak"

# ==============================================================================
# 4. Read Test Content
# ==============================================================================
TEST_CONTENT=""
if [ "$TEST_EXISTS" = "true" ]; then
    TEST_CONTENT=$(cat "$TEST_FILE")
fi

# Escaping for JSON
POM_ESCAPED=$(echo "$POM_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
TEST_ESCAPED=$(echo "$TEST_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# ==============================================================================
# 5. Generate JSON Result
# ==============================================================================
RESULT_JSON=$(cat << EOF
{
    "task_start": $TASK_START,
    "task_end": $(date +%s),
    "test_file_exists": $TEST_EXISTS,
    "test_created_during_task": $TEST_CREATED_DURING_TASK,
    "has_junit_dependency": $HAS_JUNIT,
    "has_mockito_dependency": $HAS_MOCKITO,
    "baseline_tests_pass": $BASELINE_PASS,
    "mutant_a_caught": $MUTANT_A_CAUGHT,
    "mutant_b_caught": $MUTANT_B_CAUGHT,
    "mutant_c_caught": $MUTANT_C_CAUGHT,
    "pom_content": $POM_ESCAPED,
    "test_content": $TEST_ESCAPED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="