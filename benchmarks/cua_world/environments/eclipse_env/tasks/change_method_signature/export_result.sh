#!/bin/bash
echo "=== Exporting change_method_signature result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/PaymentPlatform"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Compile project to verify code validity (using Maven headless)
echo "Verifying compilation..."
cd "$PROJECT_DIR"
if mvn compile -q -DskipTests > /tmp/mvn_compile.log 2>&1; then
    COMPILATION_SUCCESS="true"
else
    COMPILATION_SUCCESS="false"
fi

# 2. Check timestamps against start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Function to check file mod time
check_modified() {
    local f="$1"
    if [ -f "$f" ]; then
        local mtime=$(stat -c %Y "$f")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
        else
            echo "false"
        fi
    else
        echo "false"
    fi
}

# 3. Create JSON payload with content of key files for the verifier
# We'll put file content into the JSON so python can parse it easily
# Note: In a real large project we wouldn't dump all files, but here it's efficient

# Helper to escape JSON string
json_escape() {
    python3 -c "import json, sys; print(json.dumps(sys.stdin.read()))"
}

# Read files
SERVICE_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/acme/payment/PaymentService.java" 2>/dev/null | json_escape)
ORDER_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/acme/payment/OrderProcessor.java" 2>/dev/null | json_escape)
SUB_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/acme/payment/SubscriptionManager.java" 2>/dev/null | json_escape)
REFUND_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/acme/payment/RefundHandler.java" 2>/dev/null | json_escape)
BATCH_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/acme/payment/BatchProcessor.java" 2>/dev/null | json_escape)
CHECKOUT_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/acme/payment/CheckoutController.java" 2>/dev/null | json_escape)
TEST_CONTENT=$(cat "$PROJECT_DIR/src/test/java/com/acme/payment/PaymentServiceTest.java" 2>/dev/null | json_escape)

# Check modification status
SERVICE_MOD=$(check_modified "$PROJECT_DIR/src/main/java/com/acme/payment/PaymentService.java")
ORDER_MOD=$(check_modified "$PROJECT_DIR/src/main/java/com/acme/payment/OrderProcessor.java")

# Construct JSON
RESULT_JSON=$(cat << EOF
{
    "compilation_success": $COMPILATION_SUCCESS,
    "service_modified": $SERVICE_MOD,
    "order_modified": $ORDER_MOD,
    "files": {
        "PaymentService.java": $SERVICE_CONTENT,
        "OrderProcessor.java": $ORDER_CONTENT,
        "SubscriptionManager.java": $SUB_CONTENT,
        "RefundHandler.java": $REFUND_CONTENT,
        "BatchProcessor.java": $BATCH_CONTENT,
        "CheckoutController.java": $CHECKOUT_CONTENT,
        "PaymentServiceTest.java": $TEST_CONTENT
    },
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="