#!/bin/bash
set -e
echo "=== Exporting add_retrofit_networking result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/PostViewer"
APP_DIR="$PROJECT_DIR/app"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Paths to verify
BUILD_GRADLE="$APP_DIR/build.gradle.kts"
MANIFEST="$APP_DIR/src/main/AndroidManifest.xml"
POST_MODEL="$APP_DIR/src/main/java/com/example/postviewer/model/Post.kt"
API_SERVICE="$APP_DIR/src/main/java/com/example/postviewer/network/PostApiService.kt"
API_CLIENT="$APP_DIR/src/main/java/com/example/postviewer/network/ApiClient.kt"

# Helper to read file content safely
read_file_safe() {
    if [ -f "$1" ]; then
        cat "$1"
    else
        echo ""
    fi
}

# Helper to get file timestamp
get_timestamp() {
    if [ -f "$1" ]; then
        stat -c %Y "$1"
    else
        echo "0"
    fi
}

# 1. Capture file contents
CONTENT_BUILD_GRADLE=$(read_file_safe "$BUILD_GRADLE")
CONTENT_MANIFEST=$(read_file_safe "$MANIFEST")
CONTENT_POST=$(read_file_safe "$POST_MODEL")
CONTENT_SERVICE=$(read_file_safe "$API_SERVICE")
CONTENT_CLIENT=$(read_file_safe "$API_CLIENT")

# 2. Capture timestamps
TIME_POST=$(get_timestamp "$POST_MODEL")
TIME_SERVICE=$(get_timestamp "$API_SERVICE")
TIME_CLIENT=$(get_timestamp "$API_CLIENT")
TIME_GRADLE=$(get_timestamp "$BUILD_GRADLE")
TIME_MANIFEST=$(get_timestamp "$MANIFEST")

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Attempt Build
BUILD_SUCCESS="false"
BUILD_OUTPUT=""

if [ -f "$PROJECT_DIR/gradlew" ]; then
    echo "Running gradle assembleDebug..."
    cd "$PROJECT_DIR"
    chmod +x gradlew
    
    # Run gradle with environment variables
    BUILD_LOG=$(mktemp)
    
    su - ga -c "cd $PROJECT_DIR && export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 && ./gradlew assembleDebug --no-daemon" > "$BUILD_LOG" 2>&1 || true
    
    if grep -q "BUILD SUCCESSFUL" "$BUILD_LOG"; then
        BUILD_SUCCESS="true"
    fi
    
    BUILD_OUTPUT=$(cat "$BUILD_LOG" | tail -n 50)
    rm -f "$BUILD_LOG"
else
    echo "gradlew not found, skipping command line build check"
    BUILD_OUTPUT="gradlew missing"
fi

# 4. JSON Export
# Use python for safe JSON encoding
python3 -c "
import json
import os

data = {
    'task_start': $TASK_START,
    'files': {
        'build_gradle': {
            'content': '''$CONTENT_BUILD_GRADLE''',
            'mtime': $TIME_GRADLE
        },
        'manifest': {
            'content': '''$CONTENT_MANIFEST''',
            'mtime': $TIME_MANIFEST
        },
        'post_model': {
            'content': '''$CONTENT_POST''',
            'mtime': $TIME_POST
        },
        'api_service': {
            'content': '''$CONTENT_SERVICE''',
            'mtime': $TIME_SERVICE
        },
        'api_client': {
            'content': '''$CONTENT_CLIENT''',
            'mtime': $TIME_CLIENT
        }
    },
    'build': {
        'success': $BUILD_SUCCESS, # Python reads True/False from 'true'/'false' literal if we handle it, but here it's raw string
        'output': '''$BUILD_OUTPUT'''
    }
}

# Fix booleans manually if needed or just use strings
data['build']['success'] = True if '$BUILD_SUCCESS' == 'true' else False

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
"

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result size: $(stat -c %s /tmp/task_result.json)"