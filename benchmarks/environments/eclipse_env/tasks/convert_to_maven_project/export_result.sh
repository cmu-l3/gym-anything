#!/bin/bash
echo "=== Exporting convert_to_maven_project result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/DateUtilsLegacy"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# ------------------------------------------------------------------
# Collect File Evidence
# ------------------------------------------------------------------

# Check 1: .project file (for Maven nature)
DOT_PROJECT_EXISTS="false"
DOT_PROJECT_CONTENT=""
if [ -f "$PROJECT_DIR/.project" ]; then
    DOT_PROJECT_EXISTS="true"
    DOT_PROJECT_CONTENT=$(cat "$PROJECT_DIR/.project" 2>/dev/null)
fi

# Check 2: pom.xml (for coordinates and dependencies)
POM_EXISTS="false"
POM_CONTENT=""
POM_MTIME="0"
if [ -f "$PROJECT_DIR/pom.xml" ]; then
    POM_EXISTS="true"
    POM_CONTENT=$(cat "$PROJECT_DIR/pom.xml" 2>/dev/null)
    POM_MTIME=$(stat -c %Y "$PROJECT_DIR/pom.xml" 2>/dev/null || echo "0")
fi

# Check 3: .classpath (for Maven container vs manual JAR)
CLASSPATH_EXISTS="false"
CLASSPATH_CONTENT=""
if [ -f "$PROJECT_DIR/.classpath" ]; then
    CLASSPATH_EXISTS="true"
    CLASSPATH_CONTENT=$(cat "$PROJECT_DIR/.classpath" 2>/dev/null)
fi

# Check 4: Build Artifacts (Did it compile?)
# Maven usually compiles to target/classes
CLASS_FILES_EXIST="false"
if [ -d "$PROJECT_DIR/target/classes" ]; then
    if find "$PROJECT_DIR/target/classes" -name "*.class" | grep -q "."; then
        CLASS_FILES_EXIST="true"
    fi
fi
# Also check legacy bin/ folder just in case
BIN_FILES_EXIST="false"
if [ -d "$PROJECT_DIR/bin" ]; then
    if find "$PROJECT_DIR/bin" -name "*.class" | grep -q "."; then
        BIN_FILES_EXIST="true"
    fi
fi

# ------------------------------------------------------------------
# Prepare JSON Output
# ------------------------------------------------------------------

# Escape content for JSON safely using python
DOT_PROJECT_ESCAPED=$(echo "$DOT_PROJECT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
POM_ESCAPED=$(echo "$POM_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
CLASSPATH_ESCAPED=$(echo "$CLASSPATH_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

RESULT_JSON=$(cat << EOF
{
    "task_start_time": $TASK_START_TIME,
    "project_exists": $DOT_PROJECT_EXISTS,
    "pom_exists": $POM_EXISTS,
    "pom_mtime": $POM_MTIME,
    "classpath_exists": $CLASSPATH_EXISTS,
    "class_files_exist": $CLASS_FILES_EXIST,
    "bin_files_exist": $BIN_FILES_EXIST,
    "dot_project_content": $DOT_PROJECT_ESCAPED,
    "pom_content": $POM_ESCAPED,
    "classpath_content": $CLASSPATH_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="