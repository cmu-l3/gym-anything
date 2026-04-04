#!/bin/bash
echo "=== Exporting reorganize_package_structure result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/ShopManager"
JAVA_SRC_ROOT="$PROJECT_DIR/src/main/java"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Verify Compilation
# We run maven compile to see if the project is valid
echo "Running compilation check..."
cd "$PROJECT_DIR"
if run_maven "$PROJECT_DIR" "clean compile" "/tmp/mvn_build.log"; then
    BUILD_SUCCESS="true"
else
    BUILD_SUCCESS="false"
fi
# Capture build errors if any
BUILD_LOG_TAIL=$(tail -n 20 /tmp/mvn_build.log | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

# 3. Analyze File Structure
# We define a function to check a file's location and package declaration
check_file() {
    local filename="$1"
    local expected_suffix="$2" # e.g., com/myapp/model
    local actual_path=$(find "$JAVA_SRC_ROOT" -name "$filename" 2>/dev/null)
    
    local found="false"
    local package_decl=""
    local correct_loc="false"
    
    if [ -n "$actual_path" ]; then
        found="true"
        # Extract package declaration: "package com.myapp.model;"
        package_decl=$(grep "^package " "$actual_path" | head -1 | sed 's/package //;s/;//' | tr -d '\r')
        
        # Check if path ends with expected structure
        if [[ "$actual_path" == *"$expected_suffix/$filename" ]]; then
            correct_loc="true"
        fi
    fi
    
    echo "{\"filename\": \"$filename\", \"found\": $found, \"path\": \"$actual_path\", \"package\": \"$package_decl\", \"correct_location\": $correct_loc}"
}

# Check all files
FILES_JSON=""
FILES_LIST=(
    "User.java|com/myapp/model"
    "Product.java|com/myapp/model"
    "Order.java|com/myapp/model"
    "UserService.java|com/myapp/service"
    "ProductService.java|com/myapp/service"
    "OrderService.java|com/myapp/service"
    "StringUtils.java|com/myapp/util"
    "DateUtils.java|com/myapp/util"
    "AppConfig.java|com/myapp/config"
    "App.java|com/myapp"
)

FIRST="true"
for item in "${FILES_LIST[@]}"; do
    IFS="|" read -r fname expected <<< "$item"
    if [ "$FIRST" = "true" ]; then
        FILES_JSON="$(check_file "$fname" "$expected")"
        FIRST="false"
    else
        FILES_JSON="$FILES_JSON, $(check_file "$fname" "$expected")"
    fi
done

# 4. Check if old directory is empty/gone
OLD_DIR="$JAVA_SRC_ROOT/myapp"
OLD_DIR_CLEAN="false"
if [ ! -d "$OLD_DIR" ]; then
    OLD_DIR_CLEAN="true"
elif [ -z "$(ls -A "$OLD_DIR")" ]; then
    OLD_DIR_CLEAN="true"
fi

# 5. Generate Result JSON
RESULT_JSON=$(cat << EOF
{
    "build_success": $BUILD_SUCCESS,
    "build_log": $BUILD_LOG_TAIL,
    "old_directory_clean": $OLD_DIR_CLEAN,
    "file_checks": [$FILES_JSON],
    "timestamp": "$(date -Iseconds)",
    "task_start": $TASK_START
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="