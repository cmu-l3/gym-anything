#!/bin/bash
echo "=== Exporting generate_data_class_methods result ==="
source /workspace/scripts/task_utils.sh

PROJECT_ROOT="/home/ga/IdeaProjects/data-models"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Run compilation check
echo "Running compilation..."
COMPILE_SUCCESS="false"
COMPILE_OUTPUT=""

if [ -f "$PROJECT_ROOT/pom.xml" ]; then
    cd "$PROJECT_ROOT"
    # Capture both stdout and stderr
    COMPILE_OUTPUT=$(su - ga -c "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; mvn compile" 2>&1)
    if [ $? -eq 0 ]; then
        COMPILE_SUCCESS="true"
    fi
fi

# 3. Check file modification times (Anti-gaming)
# If files haven't been touched since start, agent didn't do anything
FILES_MODIFIED="false"
PERSON_MTIME=$(stat -c %Y "$PROJECT_ROOT/src/main/java/com/example/models/Person.java" 2>/dev/null || echo "0")
ADDRESS_MTIME=$(stat -c %Y "$PROJECT_ROOT/src/main/java/com/example/models/Address.java" 2>/dev/null || echo "0")
ORDER_MTIME=$(stat -c %Y "$PROJECT_ROOT/src/main/java/com/example/models/Order.java" 2>/dev/null || echo "0")

if [ "$PERSON_MTIME" -gt "$TASK_START" ] || \
   [ "$ADDRESS_MTIME" -gt "$TASK_START" ] || \
   [ "$ORDER_MTIME" -gt "$TASK_START" ]; then
    FILES_MODIFIED="true"
fi

# 4. Check for .class files (Evidence of successful compile)
CLASS_FILES_EXIST="false"
if [ -f "$PROJECT_ROOT/target/classes/com/example/models/Person.class" ] && \
   [ -f "$PROJECT_ROOT/target/classes/com/example/models/Address.class" ] && \
   [ -f "$PROJECT_ROOT/target/classes/com/example/models/Order.class" ]; then
    CLASS_FILES_EXIST="true"
fi

# 5. Prepare compilation output for JSON (escape quotes/newlines)
# We use Python to safely JSON-encode the string to avoid syntax errors
COMPILE_OUTPUT_JSON=$(echo "$COMPILE_OUTPUT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

# 6. Create result JSON
cat > /tmp/task_result.json << EOF
{
    "compile_success": $COMPILE_SUCCESS,
    "compile_output": $COMPILE_OUTPUT_JSON,
    "files_modified": $FILES_MODIFIED,
    "class_files_exist": $CLASS_FILES_EXIST,
    "task_start_time": $TASK_START,
    "person_mtime": $PERSON_MTIME,
    "address_mtime": $ADDRESS_MTIME,
    "order_mtime": $ORDER_MTIME
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="