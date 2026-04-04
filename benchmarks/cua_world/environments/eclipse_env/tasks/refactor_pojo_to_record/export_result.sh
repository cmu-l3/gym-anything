#!/bin/bash
echo "=== Exporting refactor_pojo_to_record result ==="

source /workspace/scripts/task_utils.sh

PROJECT_ROOT="/home/ga/eclipse-workspace/RadiationTherapy"

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Attempt to compile and run tests (headless)
# We use su - ga to run as user, preserving environment
echo "Running Maven build..."
cd "$PROJECT_ROOT"
su - ga -c "cd $PROJECT_ROOT && mvn clean compile test > /tmp/mvn_output.log 2>&1" || true

MVN_EXIT_CODE=$?
echo "Maven exit code: $MVN_EXIT_CODE"

# 3. Inspect the bytecode to verify it's a Record
# We check BeamSetup.class
CLASS_FILE="$PROJECT_ROOT/target/classes/com/medsys/rt/model/BeamSetup.class"
IS_RECORD="false"
JAVAP_OUTPUT=""

if [ -f "$CLASS_FILE" ]; then
    echo "Inspecting BeamSetup class..."
    # javap -p shows private members and class signature
    JAVAP_OUTPUT=$(javap -p "$CLASS_FILE")
    if echo "$JAVAP_OUTPUT" | grep -q "extends java.lang.Record"; then
        IS_RECORD="true"
    fi
fi

# 4. Read source files for verification
BEAM_SETUP_SRC=""
TREATMENT_PLAN_SRC=""

if [ -f "$PROJECT_ROOT/src/main/java/com/medsys/rt/model/BeamSetup.java" ]; then
    BEAM_SETUP_SRC=$(cat "$PROJECT_ROOT/src/main/java/com/medsys/rt/model/BeamSetup.java")
fi

if [ -f "$PROJECT_ROOT/src/main/java/com/medsys/rt/service/TreatmentPlan.java" ]; then
    TREATMENT_PLAN_SRC=$(cat "$PROJECT_ROOT/src/main/java/com/medsys/rt/service/TreatmentPlan.java")
fi

# 5. Check Maven output for test results
TESTS_RUN="0"
TESTS_FAILURES="0"
TESTS_ERRORS="0"
BUILD_SUCCESS="false"

if [ -f "/tmp/mvn_output.log" ]; then
    if grep -q "BUILD SUCCESS" "/tmp/mvn_output.log"; then
        BUILD_SUCCESS="true"
    fi
    
    # Extract test stats
    # Tests run: 3, Failures: 0, Errors: 0, Skipped: 0
    TEST_LINE=$(grep "Tests run:" "/tmp/mvn_output.log" | tail -1)
    if [ -n "$TEST_LINE" ]; then
        TESTS_RUN=$(echo "$TEST_LINE" | sed -n 's/.*Tests run: \([0-9]*\).*/\1/p')
        TESTS_FAILURES=$(echo "$TEST_LINE" | sed -n 's/.*Failures: \([0-9]*\).*/\1/p')
        TESTS_ERRORS=$(echo "$TEST_LINE" | sed -n 's/.*Errors: \([0-9]*\).*/\1/p')
    fi
fi

# 6. JSON Export
# Use python to escape strings safely
cat > /tmp/json_builder.py << PYEOF
import json
import os

result = {
    "build_success": $BUILD_SUCCESS,
    "is_record_bytecode": $IS_RECORD,
    "tests_run": int("$TESTS_RUN") if "$TESTS_RUN".isdigit() else 0,
    "tests_failures": int("$TESTS_FAILURES") if "$TESTS_FAILURES".isdigit() else 0,
    "tests_errors": int("$TESTS_ERRORS") if "$TESTS_ERRORS".isdigit() else 0,
    "maven_exit_code": $MVN_EXIT_CODE,
    "timestamp": "$(date -Iseconds)"
}

# Read large text contents
try:
    with open("$PROJECT_ROOT/src/main/java/com/medsys/rt/model/BeamSetup.java", "r") as f:
        result["beam_setup_src"] = f.read()
except:
    result["beam_setup_src"] = ""

try:
    with open("$PROJECT_ROOT/src/main/java/com/medsys/rt/service/TreatmentPlan.java", "r") as f:
        result["treatment_plan_src"] = f.read()
except:
    result["treatment_plan_src"] = ""
    
try:
    with open("/tmp/mvn_output.log", "r") as f:
        result["mvn_log"] = f.read()[:5000] # Truncate log
except:
    result["mvn_log"] = ""

print(json.dumps(result))
PYEOF

python3 /tmp/json_builder.py > /tmp/task_result.json

# Permission fix
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
head -n 20 /tmp/task_result.json