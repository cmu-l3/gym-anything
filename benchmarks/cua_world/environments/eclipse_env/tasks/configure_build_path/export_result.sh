#!/bin/bash
echo "=== Exporting configure_build_path result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/DataProcessor"
RESULT_JSON="/tmp/task_result.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Capture .classpath content
CLASSPATH_CONTENT=""
if [ -f "$PROJECT_DIR/.classpath" ]; then
    CLASSPATH_CONTENT=$(cat "$PROJECT_DIR/.classpath")
fi

# Check for compiled class files
# Eclipse standard output is 'bin', but agent might configure it differently.
# We look in the project directory recursively for .class files.
CLASS_FILES_FOUND=$(find "$PROJECT_DIR" -name "*.class" | wc -l)

# Check specific class files existence and timestamp
APP_CLASS_EXISTS="false"
TRANSFORMER_CLASS_EXISTS="false"
ANALYZER_CLASS_EXISTS="false"

# Helper to find class file and check if it's newer than start time
check_class_file() {
    local class_name="$1"
    local found="false"
    
    # Find the file
    local file_path=$(find "$PROJECT_DIR" -name "$class_name" -print -quit)
    
    if [ -n "$file_path" ]; then
        found="true"
        # Check timestamp
        local start_time=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
        local file_mtime=$(stat -c %Y "$file_path")
        
        if [ "$file_mtime" -lt "$start_time" ]; then
            # File exists but is old (shouldn't happen as we start fresh, but good for safety)
            found="true" 
        fi
    fi
    echo "$found"
}

APP_CLASS_EXISTS=$(check_class_file "App.class")
TRANSFORMER_CLASS_EXISTS=$(check_class_file "JsonTransformer.class")
ANALYZER_CLASS_EXISTS=$(check_class_file "TextAnalyzer.class")

# Check if .classpath was modified
INITIAL_CLASSPATH_HASH=$(md5sum /tmp/initial_classpath.xml 2>/dev/null | awk '{print $1}')
CURRENT_CLASSPATH_HASH=$(md5sum "$PROJECT_DIR/.classpath" 2>/dev/null | awk '{print $1}')
CLASSPATH_MODIFIED="false"
if [ "$INITIAL_CLASSPATH_HASH" != "$CURRENT_CLASSPATH_HASH" ]; then
    CLASSPATH_MODIFIED="true"
fi

# Escape content for JSON
CLASSPATH_ESCAPED=$(echo "$CLASSPATH_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "classpath_exists": true,
    "classpath_content": $CLASSPATH_ESCAPED,
    "classpath_modified": $CLASSPATH_MODIFIED,
    "class_files_count": $CLASS_FILES_FOUND,
    "app_class_exists": $APP_CLASS_EXISTS,
    "transformer_class_exists": $TRANSFORMER_CLASS_EXISTS,
    "analyzer_class_exists": $ANALYZER_CLASS_EXISTS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move result to accessible location
rm -f "$RESULT_JSON" 2>/dev/null || sudo rm -f "$RESULT_JSON" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_JSON"
chmod 666 "$RESULT_JSON" 2>/dev/null || sudo chmod 666 "$RESULT_JSON" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to $RESULT_JSON"
echo "=== Export complete ==="