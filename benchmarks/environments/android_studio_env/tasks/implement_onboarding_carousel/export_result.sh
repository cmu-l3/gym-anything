#!/bin/bash
echo "=== Exporting onboarding_carousel result ==="

source /workspace/scripts/task_utils.sh

# Paths
PROJECT_DIR="/home/ga/AndroidStudioProjects/TravelBuddy"
PACKAGE_PATH="$PROJECT_DIR/app/src/main/java/com/example/travelbuddy"
RES_DIR="$PROJECT_DIR/app/src/main/res"

# 1. Take Final Screenshot
take_screenshot /tmp/task_end.png

# 2. Collect File Contents
MAIN_ACTIVITY_CONTENT=""
if [ -f "$PACKAGE_PATH/MainActivity.kt" ]; then
    MAIN_ACTIVITY_CONTENT=$(cat "$PACKAGE_PATH/MainActivity.kt")
fi

ADAPTER_CONTENT=""
# Look for Adapter in package path, but user might place it elsewhere or name it slightly differently
# We assume they follow instruction "OnboardingAdapter.kt"
ADAPTER_PATH=$(find "$PACKAGE_PATH" -name "OnboardingAdapter.kt" | head -n 1)
if [ -f "$ADAPTER_PATH" ]; then
    ADAPTER_CONTENT=$(cat "$ADAPTER_PATH")
fi

ACTIVITY_XML_CONTENT=""
if [ -f "$RES_DIR/layout/activity_main.xml" ]; then
    ACTIVITY_XML_CONTENT=$(cat "$RES_DIR/layout/activity_main.xml")
fi

ITEM_XML_CONTENT=""
# User must create this file
ITEM_XML_PATH=$(find "$RES_DIR/layout" -name "item_onboarding.xml" | head -n 1)
if [ -f "$ITEM_XML_PATH" ]; then
    ITEM_XML_CONTENT=$(cat "$ITEM_XML_PATH")
fi

# 3. Attempt to Build (Check for compilation errors)
echo "Attempting build..."
BUILD_SUCCESS="false"
if [ -f "$PROJECT_DIR/gradlew" ]; then
    cd "$PROJECT_DIR"
    chmod +x gradlew
    # Use assembleDebug to verify compilation
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    ./gradlew assembleDebug --no-daemon > /tmp/gradle_output.log 2>&1
    
    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
fi

# 4. Check for Hardcoded Text (Anti-gaming)
# If the user hardcoded "Explore the World" into activity_main.xml instead of using the adapter/ViewPager,
# that's an invalid solution.
HARDCODED_IN_MAIN="false"
if echo "$ACTIVITY_XML_CONTENT" | grep -qi "Explore the World"; then
    HARDCODED_IN_MAIN="true"
fi

# 5. Escape for JSON
escape_json() {
    printf '%s' "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""'
}

MAIN_ACTIVITY_ESCAPED=$(escape_json "$MAIN_ACTIVITY_CONTENT")
ADAPTER_ESCAPED=$(escape_json "$ADAPTER_CONTENT")
ACTIVITY_XML_ESCAPED=$(escape_json "$ACTIVITY_XML_CONTENT")
ITEM_XML_ESCAPED=$(escape_json "$ITEM_XML_CONTENT")

# 6. Write Result
RESULT_JSON=$(cat << EOF
{
    "build_success": $BUILD_SUCCESS,
    "main_activity_exists": $([ -n "$MAIN_ACTIVITY_CONTENT" ] && echo "true" || echo "false"),
    "adapter_exists": $([ -n "$ADAPTER_CONTENT" ] && echo "true" || echo "false"),
    "item_xml_exists": $([ -n "$ITEM_XML_CONTENT" ] && echo "true" || echo "false"),
    "main_activity_content": $MAIN_ACTIVITY_ESCAPED,
    "adapter_content": $ADAPTER_ESCAPED,
    "activity_xml_content": $ACTIVITY_XML_ESCAPED,
    "item_xml_content": $ITEM_XML_ESCAPED,
    "hardcoded_in_main": $HARDCODED_IN_MAIN,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json
echo "Export complete."