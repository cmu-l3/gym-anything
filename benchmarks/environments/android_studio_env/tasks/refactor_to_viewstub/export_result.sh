#!/bin/bash
set -e
echo "=== Exporting refactor_to_viewstub result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/DashboardApp"
RES_LAYOUT_DIR="$PROJECT_DIR/app/src/main/res/layout"
SRC_DIR="$PROJECT_DIR/app/src/main/java/com/example/dashboardapp"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check file existence
LAYOUT_DETAILS_EXISTS="false"
LAYOUT_STATS_EXISTS="false"
ACTIVITY_EXISTS="false"

if [ -f "$RES_LAYOUT_DIR/layout_stats_details.xml" ]; then
    LAYOUT_DETAILS_EXISTS="true"
fi
if [ -f "$RES_LAYOUT_DIR/activity_stats.xml" ]; then
    LAYOUT_STATS_EXISTS="true"
fi
if [ -f "$SRC_DIR/StatsActivity.kt" ]; then
    ACTIVITY_EXISTS="true"
fi

# 3. Read file contents (safe read)
LAYOUT_DETAILS_CONTENT=""
if [ "$LAYOUT_DETAILS_EXISTS" = "true" ]; then
    LAYOUT_DETAILS_CONTENT=$(cat "$RES_LAYOUT_DIR/layout_stats_details.xml")
fi

LAYOUT_STATS_CONTENT=""
if [ "$LAYOUT_STATS_EXISTS" = "true" ]; then
    LAYOUT_STATS_CONTENT=$(cat "$RES_LAYOUT_DIR/activity_stats.xml")
fi

ACTIVITY_CONTENT=""
if [ "$ACTIVITY_EXISTS" = "true" ]; then
    ACTIVITY_CONTENT=$(cat "$SRC_DIR/StatsActivity.kt")
fi

# 4. Attempt Build to verify valid code
BUILD_SUCCESS="false"
BUILD_OUTPUT=""

if [ -f "$PROJECT_DIR/gradlew" ]; then
    echo "Running Gradle build..."
    # We use compileDebugKotlin to save time compared to full assemble
    cd "$PROJECT_DIR"
    chmod +x gradlew
    
    # Run in a subshell as 'ga' to avoid root permission issues with gradle cache
    if su - ga -c "cd $PROJECT_DIR && export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 && ./gradlew compileDebugKotlin --no-daemon" > /tmp/gradle_build.log 2>&1; then
        BUILD_SUCCESS="true"
    fi
    BUILD_OUTPUT=$(head -n 50 /tmp/gradle_build.log)
fi

# 5. JSON Construction
# Helper for escaping JSON strings
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '""'
}

ESC_DETAILS=$(escape_json "$LAYOUT_DETAILS_CONTENT")
ESC_STATS=$(escape_json "$LAYOUT_STATS_CONTENT")
ESC_ACTIVITY=$(escape_json "$ACTIVITY_CONTENT")
ESC_BUILD_OUT=$(escape_json "$BUILD_OUTPUT")

cat > /tmp/task_result.json <<EOF
{
    "layout_details_exists": $LAYOUT_DETAILS_EXISTS,
    "layout_stats_exists": $LAYOUT_STATS_EXISTS,
    "activity_exists": $ACTIVITY_EXISTS,
    "layout_details_content": $ESC_DETAILS,
    "layout_stats_content": $ESC_STATS,
    "activity_content": $ESC_ACTIVITY,
    "build_success": $BUILD_SUCCESS,
    "build_output": $ESC_BUILD_OUT,
    "timestamp": $(date +%s)
}
EOF

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="