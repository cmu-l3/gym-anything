#!/bin/bash
set -e

echo "=== Exporting add_notification_channels result ==="

PROJECT_DIR="/home/ga/AndroidStudioProjects/NotepadApp"
APP_SRC="$PROJECT_DIR/app/src/main/java/com/example/notepadapp"

# 1. Take final screenshot (Evidence of final state)
source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_final.png

# 2. Capture File Contents for Verification
# We explicitly check for files created/modified by the agent
HELPER_PATH="$APP_SRC/notifications/NotificationHelper.kt"
APP_CLASS_PATH="$APP_SRC/NotepadApplication.kt"
MANIFEST_PATH="$PROJECT_DIR/app/src/main/AndroidManifest.xml"

# Helper content
HELPER_CONTENT=""
if [ -f "$HELPER_PATH" ]; then
    HELPER_CONTENT=$(cat "$HELPER_PATH")
# Check alternate location (common mistake)
elif [ -f "$APP_SRC/NotificationHelper.kt" ]; then
    HELPER_CONTENT=$(cat "$APP_SRC/NotificationHelper.kt")
fi

# Application class content
APP_CLASS_CONTENT=""
if [ -f "$APP_CLASS_PATH" ]; then
    APP_CLASS_CONTENT=$(cat "$APP_CLASS_PATH")
fi

# Manifest content
MANIFEST_CONTENT=""
if [ -f "$MANIFEST_PATH" ]; then
    MANIFEST_CONTENT=$(cat "$MANIFEST_PATH")
fi

# 3. Check Compile Status
# Try to build only if key files exist to save time
BUILD_SUCCESS="false"
if [ -n "$HELPER_CONTENT" ] && [ -n "$APP_CLASS_CONTENT" ]; then
    echo "Attempting Gradle build..."
    cd "$PROJECT_DIR"
    
    # Run gradle as ga user
    if su - ga -c "cd $PROJECT_DIR && export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 && ./gradlew assembleDebug --no-daemon" > /tmp/gradle_build.log 2>&1; then
        BUILD_SUCCESS="true"
    else
        echo "Build failed. Log saved to /tmp/gradle_build.log"
    fi
fi

# 4. Anti-gaming: File counts
FINAL_KT_COUNT=$(find "$PROJECT_DIR/app/src/main/java" -name "*.kt" 2>/dev/null | wc -l)

# 5. Create JSON Result
# Python script to safely escape JSON strings
cat <<EOF | python3 > /tmp/task_result.json
import json

result = {
    "helper_content": """${HELPER_CONTENT}""",
    "app_class_content": """${APP_CLASS_CONTENT}""",
    "manifest_content": """${MANIFEST_CONTENT}""",
    "build_success": ${BUILD_SUCCESS},
    "final_kt_count": ${FINAL_KT_COUNT},
    "timestamp": "$(date +%s)"
}
print(json.dumps(result))
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="