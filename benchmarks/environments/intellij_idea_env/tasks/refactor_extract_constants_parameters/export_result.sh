#!/bin/bash
echo "=== Exporting Refactor Task Result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/ecommerce-pricing"
CALC_FILE="$PROJECT_DIR/src/main/java/com/example/pricing/PricingCalculator.java"
SERVICE_FILE="$PROJECT_DIR/src/main/java/com/example/pricing/CheckoutService.java"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_end.png

# 2. Check Compilation (Verification that refactoring didn't break code)
echo "Checking compilation..."
COMPILE_SUCCESS="false"
if [ -f "$PROJECT_DIR/pom.xml" ]; then
    cd "$PROJECT_DIR"
    if JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile -q -B > /tmp/mvn_compile.log 2>&1; then
        COMPILE_SUCCESS="true"
    else
        echo "Compilation failed. Log:"
        head -n 20 /tmp/mvn_compile.log
    fi
fi

# 3. Read File Contents
CALC_CONTENT=""
SERVICE_CONTENT=""
[ -f "$CALC_FILE" ] && CALC_CONTENT=$(cat "$CALC_FILE")
[ -f "$SERVICE_FILE" ] && SERVICE_CONTENT=$(cat "$SERVICE_FILE")

# 4. Check for File Modifications
CALC_MODIFIED="false"
SERVICE_MODIFIED="false"

if [ -f /tmp/initial_calc_hash.txt ]; then
    CURRENT_HASH=$(md5sum "$CALC_FILE" | awk '{print $1}')
    INITIAL_HASH=$(awk '{print $1}' /tmp/initial_calc_hash.txt)
    [ "$CURRENT_HASH" != "$INITIAL_HASH" ] && CALC_MODIFIED="true"
fi

if [ -f /tmp/initial_service_hash.txt ]; then
    CURRENT_HASH=$(md5sum "$SERVICE_FILE" | awk '{print $1}')
    INITIAL_HASH=$(awk '{print $1}' /tmp/initial_service_hash.txt)
    [ "$CURRENT_HASH" != "$INITIAL_HASH" ] && SERVICE_MODIFIED="true"
fi

# 5. Prepare Result JSON
# Using python to safely escape content
RESULT_JSON=$(python3 -c "
import json
import os

print(json.dumps({
    'compile_success': '$COMPILE_SUCCESS' == 'true',
    'calc_content': '''$CALC_CONTENT''',
    'service_content': '''$SERVICE_CONTENT''',
    'calc_modified': '$CALC_MODIFIED' == 'true',
    'service_modified': '$SERVICE_MODIFIED' == 'true',
    'timestamp': '$(date -Iseconds)'
}))
")

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="