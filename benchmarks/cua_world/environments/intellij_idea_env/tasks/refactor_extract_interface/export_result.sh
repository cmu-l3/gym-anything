#!/bin/bash
echo "=== Exporting refactor_extract_interface result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/payment-platform"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# Paths to relevant files
INTERFACE_PATH="$PROJECT_DIR/src/main/java/com/platform/payment/PaymentGateway.java"
STRIPE_PATH="$PROJECT_DIR/src/main/java/com/platform/payment/StripeService.java"
CHECKOUT_PATH="$PROJECT_DIR/src/main/java/com/platform/service/CheckoutService.java"

# 1. Check if interface file was created
INTERFACE_EXISTS="false"
INTERFACE_CREATED_DURING_TASK="false"
INTERFACE_CONTENT=""

if [ -f "$INTERFACE_PATH" ]; then
    INTERFACE_EXISTS="true"
    INTERFACE_MTIME=$(stat -c %Y "$INTERFACE_PATH" 2>/dev/null || echo "0")
    if [ "$INTERFACE_MTIME" -gt "$TASK_START" ]; then
        INTERFACE_CREATED_DURING_TASK="true"
    fi
    INTERFACE_CONTENT=$(cat "$INTERFACE_PATH")
fi

# 2. Read content of StripeService (to check for 'implements')
STRIPE_CONTENT=""
if [ -f "$STRIPE_PATH" ]; then
    STRIPE_CONTENT=$(cat "$STRIPE_PATH")
fi

# 3. Read content of CheckoutService (to check for dependency update)
CHECKOUT_CONTENT=""
if [ -f "$CHECKOUT_PATH" ]; then
    CHECKOUT_CONTENT=$(cat "$CHECKOUT_PATH")
fi

# 4. Attempt to compile the project to ensure refactoring didn't break build
BUILD_SUCCESS="false"
BUILD_OUTPUT=""
if [ -f "$PROJECT_DIR/pom.xml" ]; then
    cd "$PROJECT_DIR"
    BUILD_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile -q 2>&1)
    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
fi

# Check if application is running
APP_RUNNING=$(pgrep -f "idea" > /dev/null && echo "true" || echo "false")

# Helper python script to escape JSON strings safely
escape_json() {
    python3 -c "import json, sys; print(json.dumps(sys.stdin.read()))"
}

# Create JSON payload
# Note: passing content through python to escape newlines/quotes
ESCAPED_INTERFACE=$(echo "$INTERFACE_CONTENT" | escape_json)
ESCAPED_STRIPE=$(echo "$STRIPE_CONTENT" | escape_json)
ESCAPED_CHECKOUT=$(echo "$CHECKOUT_CONTENT" | escape_json)
ESCAPED_BUILD_OUT=$(echo "$BUILD_OUTPUT" | tail -n 20 | escape_json)

cat > /tmp/raw_result.json <<EOF
{
    "task_start": $TASK_START,
    "interface_exists": $INTERFACE_EXISTS,
    "interface_created_during_task": $INTERFACE_CREATED_DURING_TASK,
    "interface_content": $ESCAPED_INTERFACE,
    "stripe_service_content": $ESCAPED_STRIPE,
    "checkout_service_content": $ESCAPED_CHECKOUT,
    "build_success": $BUILD_SUCCESS,
    "build_output": $ESCAPED_BUILD_OUT,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_end.png"
}
EOF

# Move to final location safely
mv /tmp/raw_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="