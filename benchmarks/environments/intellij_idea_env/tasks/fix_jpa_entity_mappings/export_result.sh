#!/bin/bash
echo "=== Exporting fix_jpa_entity_mappings result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/inventory-orm"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Run Tests
echo "Running tests..."
TEST_OUTPUT_FILE="/tmp/maven_test_output.log"
cd "$PROJECT_DIR"
# Force update snapshots/dependencies to ensure clean run
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn clean test -Dsurefire.useFile=false > "$TEST_OUTPUT_FILE" 2>&1
MVN_EXIT_CODE=$?

# 2. Capture File Contents for Verification
cat_file="$PROJECT_DIR/src/main/java/com/example/inventory/model/Category.java"
prod_file="$PROJECT_DIR/src/main/java/com/example/inventory/model/Product.java"

if [ -f "$cat_file" ]; then
    CAT_CONTENT=$(cat "$cat_file")
else
    CAT_CONTENT=""
fi

if [ -f "$prod_file" ]; then
    PROD_CONTENT=$(cat "$prod_file")
else
    PROD_CONTENT=""
fi

# 3. Check for Schema Modification (Anti-Gaming)
SCHEMA_HASH_CURRENT=$(md5sum "$PROJECT_DIR/src/main/resources/schema.sql" | awk '{print $1}')
SCHEMA_HASH_INITIAL=$(cat /tmp/initial_schema_hash.txt | awk '{print $1}')
SCHEMA_MODIFIED="false"
if [ "$SCHEMA_HASH_CURRENT" != "$SCHEMA_HASH_INITIAL" ]; then
    SCHEMA_MODIFIED="true"
fi

# 4. JSON Escape Python Script
PYTHON_ESCAPE_SCRIPT="
import json, sys
content = sys.stdin.read()
print(json.dumps(content))
"

CAT_ESCAPED=$(echo "$CAT_CONTENT" | python3 -c "$PYTHON_ESCAPE_SCRIPT")
PROD_ESCAPED=$(echo "$PROD_CONTENT" | python3 -c "$PYTHON_ESCAPE_SCRIPT")
TEST_OUT_ESCAPED=$(cat "$TEST_OUTPUT_FILE" | tail -n 50 | python3 -c "$PYTHON_ESCAPE_SCRIPT")

# 5. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "mvn_exit_code": $MVN_EXIT_CODE,
    "schema_modified": $SCHEMA_MODIFIED,
    "category_content": $CAT_ESCAPED,
    "product_content": $PROD_ESCAPED,
    "test_output_tail": $TEST_OUT_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json
echo "Result exported to /tmp/task_result.json"