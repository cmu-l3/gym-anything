#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting JaCoCo Coverage Task Results ==="

PROJECT_DIR="/home/ga/AndroidStudioProjects/WeatherApp"
BUILD_GRADLE="$PROJECT_DIR/app/build.gradle.kts"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# --- Check 1: File Modification (Anti-Gaming) ---
FILE_MODIFIED="false"
CURRENT_MD5=$(md5sum "$BUILD_GRADLE" 2>/dev/null | awk '{print $1}')
INITIAL_MD5=$(cat /tmp/initial_build_gradle_md5.txt 2>/dev/null | awk '{print $1}')

if [ -n "$CURRENT_MD5" ] && [ -n "$INITIAL_MD5" ] && [ "$CURRENT_MD5" != "$INITIAL_MD5" ]; then
    FILE_MODIFIED="true"
fi

# --- Check 2: Verify Build Configuration via Gradle ---
# We run the task to see if it executes successfully and produces the report
# This validates syntax, logic, and configuration all at once.

GRADLE_EXIT_CODE=1
REPORT_GENERATED="false"
REPORT_SIZE=0

if [ "$FILE_MODIFIED" = "true" ]; then
    echo "Running Gradle jacocoTestReport task..."
    
    # Run as user ga
    # Use || true to prevent script exit on build failure, we want to record the failure
    su - ga -c "cd $PROJECT_DIR && export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 && export ANDROID_SDK_ROOT=/opt/android-sdk && ./gradlew jacocoTestReport --no-daemon" > /tmp/gradle_output.log 2>&1 || true
    GRADLE_EXIT_CODE=$?
    
    # Check if report exists
    REPORT_PATH="$PROJECT_DIR/app/build/reports/jacoco/jacocoTestReport/html/index.html"
    if [ -f "$REPORT_PATH" ]; then
        REPORT_GENERATED="true"
        REPORT_SIZE=$(stat -c%s "$REPORT_PATH" 2>/dev/null || echo "0")
    fi
fi

# --- Check 3: Capture build.gradle.kts content ---
# We escape this for JSON embedding
BUILD_GRADLE_CONTENT=""
if [ -f "$BUILD_GRADLE" ]; then
    BUILD_GRADLE_CONTENT=$(cat "$BUILD_GRADLE")
fi

# Safe JSON string escaping (Python is reliable for this)
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

ESCAPED_CONTENT=$(escape_json "$BUILD_GRADLE_CONTENT")
ESCAPED_LOG=$(escape_json "$(tail -n 50 /tmp/gradle_output.log 2>/dev/null || echo '')")

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_modified": $FILE_MODIFIED,
    "gradle_exit_code": $GRADLE_EXIT_CODE,
    "report_generated": $REPORT_GENERATED,
    "report_size": $REPORT_SIZE,
    "build_gradle_content": $ESCAPED_CONTENT,
    "gradle_log_tail": $ESCAPED_LOG,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="