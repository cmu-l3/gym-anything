#!/bin/bash
echo "=== Exporting software_dependency_audit result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
REPO_PATH="/opt/openice/mdpnp"
REPORT_PATH="/home/ga/Desktop/openice_dependency_audit.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Analyze Report File
REPORT_EXISTS="false"
REPORT_SIZE="0"
REPORT_MTIME="0"
REPORT_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Check if created after task start
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content (escape for JSON)
    # We limit size to avoid issues with huge JSONs, but 10KB is plenty for this report
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 10000 | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
else
    REPORT_CONTENT="\"\""
fi

# 2. Extract Ground Truth from Repository (to verify agent's findings)
echo "Extracting ground truth from repository..."

# Ground Truth: Modules (from settings.gradle)
# Look for 'include' statements, clean up quotes and colons
GT_MODULES=$(grep "include " "$REPO_PATH/settings.gradle" 2>/dev/null | sed "s/'/\"/g" | grep -o "\"[^\"]*\"" | tr -d '"' | tr '\n' ',' | sed 's/,$//')
if [ -z "$GT_MODULES" ]; then
    # Fallback if settings.gradle format is different or Kotlin DSL
    GT_MODULES=$(find "$REPO_PATH" -maxdepth 2 -name "build.gradle" -o -name "build.gradle.kts" | awk -F/ '{print $(NF-1)}' | tr '\n' ',' | sed 's/,$//')
fi

# Ground Truth: Dependencies (from build.gradle files)
# Grep for implementation/api/compile, clean up to get artifact names
# We look in the main demo-apps and root
GT_DEPENDENCIES=$(grep -rE "implementation|api|compile" "$REPO_PATH" --include="build.gradle" --include="build.gradle.kts" | grep -v "project(" | grep -oE "['\"][a-zA-Z0-9\._-]+:[a-zA-Z0-9\._-]+:?[a-zA-Z0-9\._-]*['\"]" | tr -d "'\"" | sort | uniq | tr '\n' ',' | sed 's/,$//')

# Ground Truth: Gradle Version
GT_GRADLE_VERSION=$(grep "distributionUrl" "$REPO_PATH/gradle/wrapper/gradle-wrapper.properties" 2>/dev/null | grep -oE "gradle-[0-9\.]+(-[a-z]+)?-bin" | sed 's/-bin//' | sed 's/gradle-//')

# Ground Truth: DDS Implementation
# Search for known DDS vendors in file content
GT_DDS_VENDOR="Unknown"
if grep -riq "rti" "$REPO_PATH"; then
    GT_DDS_VENDOR="RTI Connext"
elif grep -riq "opendds" "$REPO_PATH"; then
    GT_DDS_VENDOR="OpenDDS"
elif grep -riq "vortex" "$REPO_PATH" || grep -riq "prismtech" "$REPO_PATH"; then
    GT_DDS_VENDOR="Vortex"
fi
# OpenICE specifically uses RTI often, but let's check for "ice" or "dds" libs
GT_DDS_HINTS=$(grep -riE "dds|rti|ndds" "$REPO_PATH/build.gradle" "$REPO_PATH/interop-lab/demo-apps/build.gradle" 2>/dev/null | head -5 | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $(date +%s),
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_content_raw": $REPORT_CONTENT,
    "ground_truth": {
        "modules": "$GT_MODULES",
        "dependencies": "$GT_DEPENDENCIES",
        "gradle_version": "$GT_GRADLE_VERSION",
        "dds_vendor": "$GT_DDS_VENDOR",
        "dds_hints": $GT_DDS_HINTS
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="