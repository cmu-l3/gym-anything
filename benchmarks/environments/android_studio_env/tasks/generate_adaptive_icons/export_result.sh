#!/bin/bash
echo "=== Exporting generate_adaptive_icons result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Paths
PROJECT_DIR="/home/ga/AndroidStudioProjects/SummitApp"
RES_DIR="$PROJECT_DIR/app/src/main/res"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Files Existence and Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Helper to check file status
check_file() {
    local path="$1"
    if [ -f "$path" ]; then
        local mtime=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "modified"
        else
            echo "exists_old"
        fi
    else
        echo "missing"
    fi
}

# Check key files
STATUS_ADAPTIVE_XML=$(check_file "$RES_DIR/mipmap-anydpi-v26/ic_launcher.xml")
STATUS_ROUND_XML=$(check_file "$RES_DIR/mipmap-anydpi-v26/ic_launcher_round.xml")
STATUS_FOREGROUND=$(check_file "$RES_DIR/drawable/ic_launcher_foreground.xml")
# Note: Sometimes AS puts foreground in drawable-v24 or similar, check fallback
if [ "$STATUS_FOREGROUND" == "missing" ]; then
    STATUS_FOREGROUND=$(check_file "$RES_DIR/drawable-v24/ic_launcher_foreground.xml")
fi
STATUS_BACKGROUND=$(check_file "$RES_DIR/values/ic_launcher_background.xml")

# 2. Check Background Color Content
BG_COLOR_FOUND="false"
BG_COLOR_VALUE=""
if [ -f "$RES_DIR/values/ic_launcher_background.xml" ]; then
    # Look for the color value #263238 inside the file
    if grep -qi "263238" "$RES_DIR/values/ic_launcher_background.xml"; then
        BG_COLOR_FOUND="true"
    fi
    # Extract the actual color for feedback
    BG_COLOR_VALUE=$(grep -oE "#[0-9a-fA-F]{6}" "$RES_DIR/values/ic_launcher_background.xml" | head -1)
fi

# 3. Check Foreground Content (Basic check to see if it looks like a vector converted from SVG)
FOREGROUND_VALID="false"
if [ -f "$RES_DIR/drawable/ic_launcher_foreground.xml" ] || [ -f "$RES_DIR/drawable-v24/ic_launcher_foreground.xml" ]; then
    # Real AS conversion usually puts "M" path data
    if grep -q "pathData" "$RES_DIR/drawable/ic_launcher_foreground.xml" 2>/dev/null || \
       grep -q "pathData" "$RES_DIR/drawable-v24/ic_launcher_foreground.xml" 2>/dev/null; then
        FOREGROUND_VALID="true"
    fi
fi

# 4. Verify Build (Gradle Resource Merge)
# We run a quick resource merge task to verify the XMLs are valid
BUILD_SUCCESS="false"
if [ -f "$PROJECT_DIR/gradlew" ]; then
    echo "Verifying resources with Gradle..."
    cd "$PROJECT_DIR"
    chmod +x gradlew
    # mergeDebugResources is faster than full assemble
    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
    export ANDROID_SDK_ROOT=/opt/android-sdk
    ./gradlew mergeDebugResources --no-daemon > /tmp/gradle_resource_check.log 2>&1
    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "status_adaptive_xml": "$STATUS_ADAPTIVE_XML",
    "status_round_xml": "$STATUS_ROUND_XML",
    "status_foreground": "$STATUS_FOREGROUND",
    "status_background": "$STATUS_BACKGROUND",
    "bg_color_found": $BG_COLOR_FOUND,
    "bg_color_value": "$BG_COLOR_VALUE",
    "foreground_valid": $FOREGROUND_VALID,
    "build_success": $BUILD_SUCCESS
}
EOF

# Save result
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="