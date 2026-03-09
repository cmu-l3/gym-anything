#!/bin/bash
echo "=== Exporting Encapsulate Field Results ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/InventorySystem"
BIN_DIR="$PROJECT_DIR/bin"
SRC_DIR="$PROJECT_DIR/src"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Attempt to compile the project
# We do this to ensure we are verifying the LATEST code, even if the agent
# didn't save or Eclipse auto-build didn't finish.
echo "Compiling project..."
COMPILATION_OUTPUT=$(su - ga -c "javac -d $BIN_DIR -sourcepath $SRC_DIR $SRC_DIR/src/com/inventory/test/ProductTest.java" 2>&1)
COMPILATION_EXIT_CODE=$?

if [ $COMPILATION_EXIT_CODE -eq 0 ]; then
    COMPILATION_SUCCESS="true"
else
    COMPILATION_SUCCESS="false"
fi

# 2. Extract Bytecode Information using 'javap'
# We dump the disassembled code to text files for the verifier to parse.

# Dump Product.class (private/public visibility check)
if [ -f "$BIN_DIR/com/inventory/core/Product.class" ]; then
    javap -p "$BIN_DIR/com/inventory/core/Product.class" > /tmp/product_javap.txt
else
    echo "Product.class not found" > /tmp/product_javap.txt
fi

# Dump InventoryManager.class (reference check)
# We use '-c' to see the bytecode instructions (look for getfield vs invokevirtual)
if [ -f "$BIN_DIR/com/inventory/service/InventoryManager.class" ]; then
    javap -c -p "$BIN_DIR/com/inventory/service/InventoryManager.class" > /tmp/manager_javap.txt
else
    echo "InventoryManager.class not found" > /tmp/manager_javap.txt
fi

# 3. Create JSON Result
RESULT_JSON=$(cat << EOF
{
    "compilation_success": $COMPILATION_SUCCESS,
    "compilation_output": "$(echo "$COMPILATION_OUTPUT" | tr '\n' ' ' | sed 's/"/\\"/g')",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

# Clean up ownership for verifier access
chmod 644 /tmp/product_javap.txt
chmod 644 /tmp/manager_javap.txt
chmod 644 /tmp/task_result.json

echo "Results exported to /tmp/task_result.json"
echo "Bytecode dumps saved to /tmp/*_javap.txt"