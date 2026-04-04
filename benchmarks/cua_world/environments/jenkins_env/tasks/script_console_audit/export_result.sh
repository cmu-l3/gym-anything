#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Script Console Audit results ==="

RESULT_FILE="/tmp/script_console_audit_result.json"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# The file is expected inside the Jenkins container at /var/jenkins_home/audit_report.txt
# Since we are running in the VM that hosts docker, we can access it via docker exec
# or checking the volume mount if we knew the path. Docker exec is safer.

echo "Checking for audit report inside container..."
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_LINES=0
FILE_MOD_TIME=0

# Use docker exec to check file and get stats
if docker exec jenkins-1 test -f /var/jenkins_home/audit_report.txt 2>/dev/null; then
    FILE_EXISTS="true"
    # Get content
    FILE_CONTENT=$(docker exec jenkins-1 cat /var/jenkins_home/audit_report.txt 2>/dev/null || echo "")
    FILE_LINES=$(echo "$FILE_CONTENT" | wc -l)
    # Get modification time (epoch)
    FILE_MOD_TIME=$(docker exec jenkins-1 stat -c %Y /var/jenkins_home/audit_report.txt 2>/dev/null || echo "0")
elif docker exec jenkins_jenkins_1 test -f /var/jenkins_home/audit_report.txt 2>/dev/null; then
    # Fallback container name
    FILE_EXISTS="true"
    FILE_CONTENT=$(docker exec jenkins_jenkins_1 cat /var/jenkins_home/audit_report.txt 2>/dev/null || echo "")
    FILE_LINES=$(echo "$FILE_CONTENT" | wc -l)
    FILE_MOD_TIME=$(docker exec jenkins_jenkins_1 stat -c %Y /var/jenkins_home/audit_report.txt 2>/dev/null || echo "0")
elif docker ps --format '{{.Names}}' | grep -q "jenkins"; then
    # Dynamic container finding
    CONTAINER=$(docker ps --format '{{.Names}}' | grep "jenkins" | head -1)
    if docker exec "$CONTAINER" test -f /var/jenkins_home/audit_report.txt 2>/dev/null; then
        FILE_EXISTS="true"
        FILE_CONTENT=$(docker exec "$CONTAINER" cat /var/jenkins_home/audit_report.txt 2>/dev/null || echo "")
        FILE_LINES=$(echo "$FILE_CONTENT" | wc -l)
        FILE_MOD_TIME=$(docker exec "$CONTAINER" stat -c %Y /var/jenkins_home/audit_report.txt 2>/dev/null || echo "0")
    fi
fi

# Determine if file was created/modified during task
FILE_CREATED_DURING_TASK="false"
if [ "$FILE_EXISTS" = "true" ] && [ "$FILE_MOD_TIME" -gt "$TASK_START_TIME" ]; then
    FILE_CREATED_DURING_TASK="true"
fi

# Load Ground Truth
GT_VERSION=$(cat /tmp/ground_truth_jenkins_version.txt 2>/dev/null || echo "unknown")
GT_PLUGINS_JSON=$(cat /tmp/ground_truth_plugins.json 2>/dev/null || echo "{}")
GT_JOB_NAMES=$(cat /tmp/ground_truth_job_names.txt 2>/dev/null || echo "")

# --- Verification Logic ---

# 1. Jenkins Version Check
VERSION_IN_FILE="false"
if [ "$FILE_EXISTS" = "true" ] && echo "$FILE_CONTENT" | grep -Fq "$GT_VERSION"; then
    VERSION_IN_FILE="true"
fi

# 2. JVM/Java Info Check
JVM_IN_FILE="false"
if [ "$FILE_EXISTS" = "true" ] && echo "$FILE_CONTENT" | grep -qiE "java|jvm|jdk|jre|openjdk"; then
    JVM_IN_FILE="true"
fi

# 3. Job Coverage Check
JOBS_FOUND=0
JOBS_EXPECTED=3
for JOB in "webapp-frontend-build" "api-integration-tests" "release-deploy-pipeline"; do
    if echo "$FILE_CONTENT" | grep -q "$JOB"; then
        JOBS_FOUND=$((JOBS_FOUND + 1))
    fi
done

# 4. Plugin Analysis
MATCHED_PLUGINS=0
TOTAL_GT_PLUGINS=0
SAMPLED_VERSION_MATCHES=0
SAMPLED_VERSION_TOTAL=0

if [ "$FILE_EXISTS" = "true" ]; then
    # Extract list of GT plugins "shortName:version"
    GT_PLUGIN_LIST=$(echo "$GT_PLUGINS_JSON" | jq -r '.plugins[] | "\(.shortName):\(.version)"' 2>/dev/null || echo "")
    TOTAL_GT_PLUGINS=$(echo "$GT_PLUGINS_JSON" | jq '.plugins | length' 2>/dev/null || echo "0")

    if [ -n "$GT_PLUGIN_LIST" ]; then
        while IFS= read -r plugin_entry; do
            PLUGIN_NAME=$(echo "$plugin_entry" | cut -d: -f1)
            PLUGIN_VERSION=$(echo "$plugin_entry" | cut -d: -f2-)
            
            # Simple check: does plugin name appear?
            if echo "$FILE_CONTENT" | grep -qi "$PLUGIN_NAME"; then
                MATCHED_PLUGINS=$((MATCHED_PLUGINS + 1))
            fi

            # Sampled check: specific core plugins and their versions
            if echo "git workflow-aggregator credentials pipeline-stage-view" | grep -qw "$PLUGIN_NAME"; then
                SAMPLED_VERSION_TOTAL=$((SAMPLED_VERSION_TOTAL + 1))
                if echo "$FILE_CONTENT" | grep -q "$PLUGIN_VERSION"; then
                    SAMPLED_VERSION_MATCHES=$((SAMPLED_VERSION_MATCHES + 1))
                fi
            fi
        done <<< "$GT_PLUGIN_LIST"
    fi
fi

# 5. Rough check for plugin entries format
HAS_PLUGIN_ENTRIES="false"
PLUGIN_ENTRY_COUNT=0
if [ "$FILE_EXISTS" = "true" ]; then
    # Count lines that look like "name ... version" (digits.digits)
    PLUGIN_ENTRY_COUNT=$(echo "$FILE_CONTENT" | grep -cE '[a-z].*[0-9]+\.[0-9]+' || echo "0")
    if [ "$PLUGIN_ENTRY_COUNT" -gt 5 ]; then
        HAS_PLUGIN_ENTRIES="true"
    fi
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Build result JSON using jq
TEMP_JSON=$(mktemp /tmp/script_audit_result.XXXXXX.json)
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_created_during_task "$FILE_CREATED_DURING_TASK" \
    --argjson file_lines "$FILE_LINES" \
    --arg gt_version "$GT_VERSION" \
    --argjson version_in_file "$VERSION_IN_FILE" \
    --argjson jvm_in_file "$JVM_IN_FILE" \
    --argjson jobs_found "$JOBS_FOUND" \
    --argjson jobs_expected "$JOBS_EXPECTED" \
    --argjson matched_plugins "$MATCHED_PLUGINS" \
    --argjson total_gt_plugins "$TOTAL_GT_PLUGINS" \
    --argjson sampled_version_matches "$SAMPLED_VERSION_MATCHES" \
    --argjson sampled_version_total "$SAMPLED_VERSION_TOTAL" \
    --argjson has_plugin_entries "$HAS_PLUGIN_ENTRIES" \
    --argjson plugin_entry_count "$PLUGIN_ENTRY_COUNT" \
    '{
        file_exists: $file_exists,
        file_created_during_task: $file_created_during_task,
        file_lines: $file_lines,
        gt_version: $gt_version,
        version_in_file: $version_in_file,
        jvm_in_file: $jvm_in_file,
        jobs_found: $jobs_found,
        jobs_expected: $jobs_expected,
        matched_plugins: $matched_plugins,
        total_gt_plugins: $total_gt_plugins,
        sampled_version_matches: $sampled_version_matches,
        sampled_version_total: $sampled_version_total,
        has_plugin_entries: $has_plugin_entries,
        plugin_entry_count: $plugin_entry_count
    }' > "$TEMP_JSON"

# Move to standard result path
rm -f "$RESULT_FILE" 2>/dev/null || true
mv "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE"

echo "Results exported to $RESULT_FILE"
cat "$RESULT_FILE"