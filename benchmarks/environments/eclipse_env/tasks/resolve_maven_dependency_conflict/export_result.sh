#!/bin/bash
echo "=== Exporting resolve_maven_dependency_conflict result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/DoseCalcService"
RESULT_FILE="/tmp/task_result.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Run 'mvn dependency:tree' to verify the actual resolved dependencies
# This is the ground truth for whether the exclusion worked
echo "Running maven dependency:tree..."
mvn_tree_output=$(cd "$PROJECT_DIR" && mvn dependency:tree -Dincludes=commons-logging 2>&1)
mvn_exit_code=$?

echo "$mvn_tree_output" > /tmp/mvn_tree.txt

# Check if commons-logging is present in the tree
# If the exclusion worked, 'mvn dependency:tree -Dincludes=commons-logging' should show NO matching artifacts
# or at least not show the jar in the compile scope under httpclient
if echo "$mvn_tree_output" | grep -q "commons-logging:commons-logging:jar"; then
    COMMONS_LOGGING_PRESENT="true"
else
    COMMONS_LOGGING_PRESENT="false"
fi

# 2. Check pom.xml content
if [ -f "$PROJECT_DIR/pom.xml" ]; then
    POM_EXISTS="true"
    POM_CONTENT=$(cat "$PROJECT_DIR/pom.xml")
    
    # Check for modification time
    TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    POM_MTIME=$(stat -c %Y "$PROJECT_DIR/pom.xml" 2>/dev/null || echo "0")
    
    if [ "$POM_MTIME" -gt "$TASK_START" ]; then
        POM_MODIFIED="true"
    else
        POM_MODIFIED="false"
    fi
else
    POM_EXISTS="false"
    POM_CONTENT=""
    POM_MODIFIED="false"
fi

# 3. Check if httpclient is still there (we shouldn't delete the parent dep)
if echo "$POM_CONTENT" | grep -q "httpclient"; then
    HTTPCLIENT_PRESENT="true"
else
    HTTPCLIENT_PRESENT="false"
fi

# Prepare JSON
# Python script to safely create JSON
python3 -c "
import json
import os

result = {
    'pom_exists': '$POM_EXISTS' == 'true',
    'pom_modified': '$POM_MODIFIED' == 'true',
    'commons_logging_present_in_tree': '$COMMONS_LOGGING_PRESENT' == 'true',
    'httpclient_present_in_pom': '$HTTPCLIENT_PRESENT' == 'true',
    'mvn_exit_code': int('$mvn_exit_code'),
    'pom_content': open('$PROJECT_DIR/pom.xml').read() if '$POM_EXISTS' == 'true' else ''
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)
"

# Set permissions
chmod 666 "$RESULT_FILE"
cat "$RESULT_FILE"

echo "=== Export complete ==="