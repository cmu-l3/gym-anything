#!/bin/bash
echo "=== Exporting fix_classpath_resource_loading result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/ClimateData"
cd "$PROJECT_DIR" || exit 1

# Take final screenshot
take_screenshot /tmp/task_end.png

# Source code verification
JAVA_FILE="src/main/java/com/climate/ClimateAnalyzer.java"
JAVA_CONTENT=""
if [ -f "$JAVA_FILE" ]; then
    JAVA_CONTENT=$(cat "$JAVA_FILE")
fi

# =============================================================================
# DYNAMIC VERIFICATION (Anti-Gaming)
# =============================================================================
# Goal: Prove code loads from classpath, not filesystem.
# Strategy: 
# 1. Compile the project.
# 2. Rename the source resource file (so src/main/resources/... is invalid).
# 3. Ensure target/classes has the resource (normal Maven build behavior).
# 4. Run the code. 
# If it passes -> It's using classpath. 
# If it fails -> It's trying to read the source file directly.

echo "Running Dynamic Verification..."
mvn clean compile > /tmp/mvn_compile.log 2>&1

DYNAMIC_CHECK_PASSED="false"
DYNAMIC_LOG=""

if [ -f "target/classes/com/climate/ClimateAnalyzer.class" ]; then
    # Ensure resource is in classpath
    mkdir -p target/classes
    cp src/main/resources/global_temps.csv target/classes/global_temps.csv

    # HIDE source file
    mv src/main/resources/global_temps.csv src/main/resources/global_temps.csv.bak

    # Run the class
    echo "Running ClimateAnalyzer with source file hidden..."
    if java -cp target/classes com.climate.ClimateAnalyzer > /tmp/run_output.txt 2>&1; then
        echo "SUCCESS: Code ran successfully without source file."
        DYNAMIC_CHECK_PASSED="true"
    else
        echo "FAILURE: Code failed to run when source file was hidden."
        cat /tmp/run_output.txt
    fi
    DYNAMIC_LOG=$(cat /tmp/run_output.txt)

    # Restore source file
    mv src/main/resources/global_temps.csv.bak src/main/resources/global_temps.csv
else
    DYNAMIC_LOG="Compilation failed, cannot run dynamic check."
fi

# Run tests normally for reporting
mvn test > /tmp/mvn_test.log 2>&1
TEST_EXIT_CODE=$?
TEST_LOG=$(cat /tmp/mvn_test.log | grep -A 5 "Results:")

# Escape content for JSON
JAVA_ESCAPED=$(echo "$JAVA_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
DYN_LOG_ESCAPED=$(echo "$DYNAMIC_LOG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
TEST_LOG_ESCAPED=$(echo "$TEST_LOG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

# Create JSON result
cat > /tmp/task_result.json << EOF
{
    "java_content": $JAVA_ESCAPED,
    "dynamic_check_passed": $DYNAMIC_CHECK_PASSED,
    "dynamic_log": $DYN_LOG_ESCAPED,
    "test_exit_code": $TEST_EXIT_CODE,
    "test_log": $TEST_LOG_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="