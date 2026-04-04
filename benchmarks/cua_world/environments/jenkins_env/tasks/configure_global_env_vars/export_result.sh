#!/bin/bash
#!/bin/bash
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/configure_global_env_vars_result.json"

echo "=== Exporting results for configure_global_env_vars ==="

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check global environment variables via Script Console
# This extracts the actual running configuration from Jenkins memory
echo "Checking global environment variables..."
ENV_VARS_RAW=$(curl -s -u "$JENKINS_USER:$JENKINS_PASS" \
    -d 'script=
import groovy.json.JsonOutput
import hudson.slaves.EnvironmentVariablesNodeProperty

def props = Jenkins.instance.globalNodeProperties.getAll(EnvironmentVariablesNodeProperty.class)
def vars = [:]
props.each { p ->
    p.envVars.each { k, v ->
        vars[k] = v
    }
}
println(JsonOutput.toJson(vars))
' "$JENKINS_URL/scriptText" 2>/dev/null || echo '{}')

# Clean the output (remove any trailing whitespace/newlines)
ENV_VARS_JSON=$(echo "$ENV_VARS_RAW" | tr -d '\r' | head -1)

# Validate JSON
if ! echo "$ENV_VARS_JSON" | jq . >/dev/null 2>&1; then
    echo "WARNING: Invalid JSON from Script Console, using empty object"
    ENV_VARS_JSON='{}'
fi

echo "Global env vars found: $ENV_VARS_JSON"

# 2. Check job existence and info
JOB_NAME="EnvVar-Verification-Job"
echo "Checking job $JOB_NAME..."
JOB_JSON=$(jenkins_api "job/${JOB_NAME}/api/json" 2>/dev/null || echo '{"_class":"none"}')
JOB_EXISTS=$(echo "$JOB_JSON" | jq 'if ._class == "none" then false else true end' 2>/dev/null || echo "false")
JOB_CLASS=$(echo "$JOB_JSON" | jq -r '._class // "none"' 2>/dev/null || echo "none")

echo "Job exists: $JOB_EXISTS, class: $JOB_CLASS"

# 3. Check build info
echo "Checking last build..."
BUILD_JSON=$(jenkins_api "job/${JOB_NAME}/lastBuild/api/json" 2>/dev/null || echo '{}')
BUILD_NUMBER=$(echo "$BUILD_JSON" | jq '.number // 0' 2>/dev/null || echo "0")
BUILD_RESULT=$(echo "$BUILD_JSON" | jq -r '.result // "NONE"' 2>/dev/null || echo "NONE")
BUILD_BUILDING=$(echo "$BUILD_JSON" | jq '.building // false' 2>/dev/null || echo "false")
BUILD_TIMESTAMP=$(echo "$BUILD_JSON" | jq '.timestamp // 0' 2>/dev/null || echo "0")

echo "Build #$BUILD_NUMBER, result: $BUILD_RESULT, building: $BUILD_BUILDING"

# 4. Get console output
echo "Getting console output..."
CONSOLE_OUTPUT=$(jenkins_api "job/${JOB_NAME}/lastBuild/consoleText" 2>/dev/null || echo "")
echo "Console output length: ${#CONSOLE_OUTPUT}"

# 5. Get job config XML (for shell command verification)
echo "Getting job config XML..."
JOB_CONFIG_XML=$(jenkins_api "job/${JOB_NAME}/config.xml" 2>/dev/null || echo "<project/>")
HAS_SHELL_STEP=$(echo "$JOB_CONFIG_XML" | grep -c "hudson.tasks.Shell" 2>/dev/null || echo "0")

# 6. Get task start time
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Construct result JSON using jq to handle escaping safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
jq -n \
    --argjson env_vars "$ENV_VARS_JSON" \
    --argjson job_exists "$JOB_EXISTS" \
    --arg job_class "$JOB_CLASS" \
    --argjson has_shell_step $([ "$HAS_SHELL_STEP" -gt 0 ] && echo "true" || echo "false") \
    --argjson build_number "$BUILD_NUMBER" \
    --arg build_result "$BUILD_RESULT" \
    --argjson build_building "$BUILD_BUILDING" \
    --argjson build_timestamp "$BUILD_TIMESTAMP" \
    --arg console_output "$CONSOLE_OUTPUT" \
    --argjson task_start "$TASK_START_TIME" \
    '{
        global_env_vars: $env_vars,
        job: {
            exists: $job_exists,
            class: $job_class,
            has_shell_step: $has_shell_step
        },
        build: {
            number: $build_number,
            result: $build_result,
            building: $build_building,
            timestamp: $build_timestamp
        },
        console_output: $console_output,
        task_start_time: $task_start
    }' > "$TEMP_JSON"

# Move to final location
rm -f "$RESULT_FILE" 2>/dev/null || true
mv "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE"

echo ""
echo "=== Export complete ==="
cat "$RESULT_FILE"