#!/bin/bash
echo "=== Exporting enforce_explicit_imports result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/inventory-system"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if project compiles (CRITICAL: removing imports breaks build)
echo "Verifying compilation..."
COMPILE_SUCCESS="false"
if [ -f "$PROJECT_DIR/pom.xml" ]; then
    cd "$PROJECT_DIR"
    # Use -q (quiet) to reduce noise, verify exit code
    if JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile -q -B; then
        COMPILE_SUCCESS="true"
    fi
fi

# 3. Analyze Java files for wildcards
echo "Analyzing source files..."
# Grep for "import ...*;" patterns
# We look for lines starting with 'import', containing '*', and ending with ';'
WILDCARD_COUNT=$(grep -rE "import\s+[\w\.]+\*;" "$PROJECT_DIR/src/main/java" | wc -l)

# 4. Check for config file modification (Settings persistence)
# IntelliJ stores project-specific code style in .idea/codeStyles/Project.xml 
# OR .idea/codeStyles/codeStyleConfig.xml if "Project" scheme is selected.
SETTINGS_FOUND="false"
SETTINGS_THRESHOLD_FOUND="false"
SETTINGS_CONTENT=""

SETTINGS_FILE="$PROJECT_DIR/.idea/codeStyles/Project.xml"
if [ -f "$SETTINGS_FILE" ]; then
    SETTINGS_FOUND="true"
    SETTINGS_CONTENT=$(cat "$SETTINGS_FILE")
    # Check if we can find the specific setting (CLASS_COUNT_TO_USE_IMPORT_ON_DEMAND)
    if grep -q "CLASS_COUNT_TO_USE_IMPORT_ON_DEMAND" "$SETTINGS_FILE"; then
        SETTINGS_THRESHOLD_FOUND="true"
    fi
fi

# 5. Check if files were actually modified
FILES_MODIFIED="false"
CURRENT_HASHES=$(find "$PROJECT_DIR/src" -name "*.java" -exec md5sum {} +)
INITIAL_HASHES=$(cat /tmp/initial_file_hashes.txt 2>/dev/null || echo "")

if [ "$CURRENT_HASHES" != "$INITIAL_HASHES" ]; then
    FILES_MODIFIED="true"
fi

# 6. Read file contents for verifier analysis
PRODUCT_JAVA=$(cat "$PROJECT_DIR/src/main/java/com/inventory/model/Product.java" 2>/dev/null || echo "")
SERVICE_JAVA=$(cat "$PROJECT_DIR/src/main/java/com/inventory/service/InventoryService.java" 2>/dev/null || echo "")
UTILS_JAVA=$(cat "$PROJECT_DIR/src/main/java/com/inventory/util/FileUtils.java" 2>/dev/null || echo "")

# Escape for JSON
PRODUCT_ESC=$(echo "$PRODUCT_JAVA" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
SERVICE_ESC=$(echo "$SERVICE_JAVA" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
UTILS_ESC=$(echo "$UTILS_JAVA" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
SETTINGS_ESC=$(echo "$SETTINGS_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

# 7. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "compile_success": $COMPILE_SUCCESS,
    "wildcard_count": $WILDCARD_COUNT,
    "files_modified": $FILES_MODIFIED,
    "settings_file_exists": $SETTINGS_FOUND,
    "settings_threshold_found": $SETTINGS_THRESHOLD_FOUND,
    "settings_content": $SETTINGS_ESC,
    "product_java": $PRODUCT_ESC,
    "service_java": $SERVICE_ESC,
    "utils_java": $UTILS_ESC,
    "timestamp": $(date +%s)
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="