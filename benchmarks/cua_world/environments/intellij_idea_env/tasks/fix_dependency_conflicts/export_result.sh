#!/bin/bash
echo "=== Exporting fix_dependency_conflicts result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/data-pipeline"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Attempt to run Maven Compile and Test inside the container
echo "Running Maven verification..."
COMPILE_EXIT_CODE=1
TEST_EXIT_CODE=1

if [ -d "$PROJECT_DIR" ]; then
    cd "$PROJECT_DIR"
    
    # Run compile
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn clean compile > /tmp/mvn_compile.log 2>&1
    COMPILE_EXIT_CODE=$?
    
    # Run test (only if compile succeeded, but try anyway)
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test > /tmp/mvn_test.log 2>&1
    TEST_EXIT_CODE=$?
fi

# 2. Read POM content
POM_CONTENT=""
if [ -f "$PROJECT_DIR/pom.xml" ]; then
    POM_CONTENT=$(cat "$PROJECT_DIR/pom.xml")
fi

# 3. Check if source files were modified (Anti-gaming check)
SOURCES_MODIFIED="false"
if [ -f /tmp/initial_source_hashes.txt ]; then
    CURRENT_FETCH_HASH=$(md5sum "$PROJECT_DIR/src/main/java/com/pipeline/DataFetcher.java" 2>/dev/null | awk '{print $1}')
    CURRENT_PROC_HASH=$(md5sum "$PROJECT_DIR/src/main/java/com/pipeline/DataProcessor.java" 2>/dev/null | awk '{print $1}')
    
    INITIAL_FETCH_HASH=$(grep "DataFetcher.java" /tmp/initial_source_hashes.txt | awk '{print $1}')
    INITIAL_PROC_HASH=$(grep "DataProcessor.java" /tmp/initial_source_hashes.txt | awk '{print $1}')
    
    if [ "$CURRENT_FETCH_HASH" != "$INITIAL_FETCH_HASH" ] || [ "$CURRENT_PROC_HASH" != "$INITIAL_PROC_HASH" ]; then
        SOURCES_MODIFIED="true"
    fi
fi

# 4. Prepare JSON result
# Python is safer for JSON escaping
cat > /tmp/create_json.py << 'PYEOF'
import json
import os
import sys

try:
    with open('/tmp/mvn_compile.log', 'r') as f:
        compile_log = f.read()[-2000:] # Last 2000 chars
except:
    compile_log = ""

try:
    with open('/tmp/mvn_test.log', 'r') as f:
        test_log = f.read()[-2000:]
except:
    test_log = ""

try:
    with open('/home/ga/IdeaProjects/data-pipeline/pom.xml', 'r') as f:
        pom_content = f.read()
except:
    pom_content = ""

result = {
    "compile_exit_code": int(sys.argv[1]),
    "test_exit_code": int(sys.argv[2]),
    "sources_modified": sys.argv[3] == "true",
    "pom_content": pom_content,
    "compile_log": compile_log,
    "test_log": test_log,
    "task_start": int(sys.argv[4]),
    "task_end": int(sys.argv[5])
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

python3 /tmp/create_json.py "$COMPILE_EXIT_CODE" "$TEST_EXIT_CODE" "$SOURCES_MODIFIED" "$TASK_START" "$TASK_END"

# Permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="