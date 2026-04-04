#!/bin/bash
echo "=== Exporting refactor_push_down_method result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/LogisticsSystem"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check compilation status
# We run maven compile to see if the project is still valid
echo "Running Maven compile..."
run_maven "$PROJECT_DIR" "compile" "/tmp/maven_compile.log"
COMPILE_STATUS=$?
COMPILE_SUCCESS="false"
if [ $COMPILE_STATUS -eq 0 ]; then
    COMPILE_SUCCESS="true"
fi

# 3. Read file contents for verification
TRANSPORT_CONTENT=""
TRUCK_CONTENT=""
SHIP_CONTENT=""
DRONE_CONTENT=""

if [ -f "$PROJECT_DIR/src/main/java/com/logistics/domain/Transport.java" ]; then
    TRANSPORT_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/logistics/domain/Transport.java")
fi

if [ -f "$PROJECT_DIR/src/main/java/com/logistics/domain/Truck.java" ]; then
    TRUCK_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/logistics/domain/Truck.java")
fi

if [ -f "$PROJECT_DIR/src/main/java/com/logistics/domain/Ship.java" ]; then
    SHIP_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/logistics/domain/Ship.java")
fi

if [ -f "$PROJECT_DIR/src/main/java/com/logistics/domain/Drone.java" ]; then
    DRONE_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/logistics/domain/Drone.java")
fi

# 4. Escape contents for JSON
T_ESC=$(echo "$TRANSPORT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
TR_ESC=$(echo "$TRUCK_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
S_ESC=$(echo "$SHIP_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
D_ESC=$(echo "$DRONE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# 5. Create JSON result
RESULT_JSON=$(cat << EOF
{
    "compile_success": $COMPILE_SUCCESS,
    "transport_content": $T_ESC,
    "truck_content": $TR_ESC,
    "ship_content": $S_ESC,
    "drone_content": $D_ESC,
    "task_end_time": $(date +%s),
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="