#!/bin/bash
set -e
echo "=== Exporting configure_release_signing result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PROJECT_DIR="/home/ga/AndroidStudioProjects/WeatherApp"
REPORT_FILE="$PROJECT_DIR/signing_report.txt"

# Take final screenshot
take_screenshot /tmp/task_end.png

# ------------------------------------------------------------------
# 1. Check Keystore
# ------------------------------------------------------------------
KEYSTORE_PATH="$PROJECT_DIR/release-keystore.jks"
KEYSTORE_EXISTS="false"
KEYSTORE_VALID="false"
KEYSTORE_DETAILS=""

if [ -f "$KEYSTORE_PATH" ]; then
    KEYSTORE_EXISTS="true"
    
    # Verify keystore details using keytool
    # We use the password from the task description
    if keytool -list -v -keystore "$KEYSTORE_PATH" -storepass "Release2024!" > /tmp/keytool_output.txt 2>&1; then
        KEYSTORE_VALID="true"
        KEYSTORE_DETAILS=$(cat /tmp/keytool_output.txt)
    else
        echo "Keytool failed to open keystore with expected password" >> /tmp/keytool_output.txt
    fi
fi

# ------------------------------------------------------------------
# 2. Check Build Gradle Configuration
# ------------------------------------------------------------------
BUILD_GRADLE="$PROJECT_DIR/app/build.gradle.kts"
BUILD_GRADLE_CONTENT=""
HAS_SIGNING_CONFIG="false"
HAS_RELEASE_CONFIG="false"

if [ -f "$BUILD_GRADLE" ]; then
    BUILD_GRADLE_CONTENT=$(cat "$BUILD_GRADLE")
    
    # Simple grep check (verifier.py will do robust checks)
    if grep -q "signingConfigs" "$BUILD_GRADLE"; then
        HAS_SIGNING_CONFIG="true"
    fi
    if grep -q "signingConfig" "$BUILD_GRADLE" && grep -q "release" "$BUILD_GRADLE"; then
        HAS_RELEASE_CONFIG="true"
    fi
fi

# ------------------------------------------------------------------
# 3. Check for Release APK
# ------------------------------------------------------------------
APK_DIR="$PROJECT_DIR/app/build/outputs/apk/release"
APK_PATH=""
APK_EXISTS="false"
APK_SIGNED="false"
APK_SIGNER_DETAILS=""

# Find the apk file (name might vary)
FOUND_APK=$(find "$APK_DIR" -name "*.apk" -not -name "*unsigned*" 2>/dev/null | head -1)

if [ -n "$FOUND_APK" ]; then
    APK_PATH="$FOUND_APK"
    APK_EXISTS="true"
    
    # Verify signature using apksigner
    # apksigner is usually in build-tools. Find the latest version.
    BUILD_TOOLS_DIR=$(ls -d /opt/android-sdk/build-tools/* | sort -V | tail -1)
    APKSIGNER="$BUILD_TOOLS_DIR/apksigner"
    
    if [ -x "$APKSIGNER" ]; then
        if "$APKSIGNER" verify --verbose --print-certs "$APK_PATH" > /tmp/apksigner_output.txt 2>&1; then
            if grep -q "Verified using v1 scheme (JAR signing): true" /tmp/apksigner_output.txt || \
               grep -q "Verified using v2 scheme (APK Signature Scheme v2): true" /tmp/apksigner_output.txt; then
                APK_SIGNED="true"
            fi
            APK_SIGNER_DETAILS=$(cat /tmp/apksigner_output.txt)
        else
             echo "Apksigner verification failed" >> /tmp/apksigner_output.txt
        fi
    else
        echo "Apksigner tool not found at $APKSIGNER" >> /tmp/apksigner_output.txt
    fi
fi

# ------------------------------------------------------------------
# 4. Check Report File
# ------------------------------------------------------------------
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE")
fi

# ------------------------------------------------------------------
# 5. Check Timestamps (Anti-Gaming)
# ------------------------------------------------------------------
KEYSTORE_CREATED_DURING_TASK="false"
APK_CREATED_DURING_TASK="false"

if [ "$KEYSTORE_EXISTS" = "true" ]; then
    KS_MTIME=$(stat -c %Y "$KEYSTORE_PATH" 2>/dev/null || echo "0")
    if [ "$KS_MTIME" -gt "$TASK_START" ]; then
        KEYSTORE_CREATED_DURING_TASK="true"
    fi
fi

if [ "$APK_EXISTS" = "true" ]; then
    APK_MTIME=$(stat -c %Y "$APK_PATH" 2>/dev/null || echo "0")
    if [ "$APK_MTIME" -gt "$TASK_START" ]; then
        APK_CREATED_DURING_TASK="true"
    fi
fi

# ------------------------------------------------------------------
# 6. JSON Export
# ------------------------------------------------------------------
# Escape JSON strings
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$1"
}

KEYSTORE_DETAILS_JSON=$(escape_json "$KEYSTORE_DETAILS")
APK_SIGNER_DETAILS_JSON=$(escape_json "$APK_SIGNER_DETAILS")
BUILD_GRADLE_JSON=$(escape_json "$BUILD_GRADLE_CONTENT")
REPORT_CONTENT_JSON=$(escape_json "$REPORT_CONTENT")
APK_PATH_JSON=$(escape_json "$APK_PATH")

JSON_CONTENT=$(cat << EOF
{
    "keystore_exists": $KEYSTORE_EXISTS,
    "keystore_valid": $KEYSTORE_VALID,
    "keystore_details": $KEYSTORE_DETAILS_JSON,
    "keystore_created_during_task": $KEYSTORE_CREATED_DURING_TASK,
    "build_gradle_content": $BUILD_GRADLE_JSON,
    "has_signing_config": $HAS_SIGNING_CONFIG,
    "has_release_config": $HAS_RELEASE_CONFIG,
    "apk_exists": $APK_EXISTS,
    "apk_path": $APK_PATH_JSON,
    "apk_signed": $APK_SIGNED,
    "apk_signer_details": $APK_SIGNER_DETAILS_JSON,
    "apk_created_during_task": $APK_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_content": $REPORT_CONTENT_JSON,
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$JSON_CONTENT" "/tmp/task_result.json"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="