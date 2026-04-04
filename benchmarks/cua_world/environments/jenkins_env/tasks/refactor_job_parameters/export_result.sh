#!/bin/bash
# Export script for Refactor Job Parameters task
# Verifies configuration and runs a functional test

echo "=== Exporting Refactor Job Parameters Result ==="

source /workspace/scripts/task_utils.sh

JOB_NAME="Deploy-Service"
TEST_ENV_VAL="staging"
EXPORT_FILE="/tmp/refactor_job_result.json"

# 1. Static Configuration Check
echo "Fetching job configuration..."
CONFIG_JSON=$(jenkins_api "job/$JOB_NAME/api/json" 2>/dev/null)
CONFIG_XML=$(get_job_config "$JOB_NAME" 2>/dev/null)

# Extract parameter definitions
# We look for 'parameterDefinitions' in the JSON response
PARAMS_JSON=$(echo "$CONFIG_JSON" | jq -r '.property[] | select(._class == "hudson.model.ParametersDefinitionProperty") | .parameterDefinitions[]' 2>/dev/null)

PARAM_NAME_FOUND=$(echo "$PARAMS_JSON" | jq -r '.name' 2>/dev/null)
PARAM_TYPE_FOUND=$(echo "$PARAMS_JSON" | jq -r '._class' 2>/dev/null)
PARAM_CHOICES_FOUND=$(echo "$PARAMS_JSON" | jq -r '.choices[]' 2>/dev/null | tr '\n' ',' | sed 's/,$//')

echo "Found parameters: Name=$PARAM_NAME_FOUND, Type=$PARAM_TYPE_FOUND"

# 2. Check Shell Script Content (Static)
# We want to see if $TARGET_ENV or ${TARGET_ENV} is in the script
SHELL_SCRIPT=$(echo "$CONFIG_XML" | xmlstarlet sel -t -v "//hudson.tasks.Shell/command" 2>/dev/null)
SCRIPT_HAS_VAR="false"
if [[ "$SHELL_SCRIPT" == *"\$TARGET_ENV"* ]] || [[ "$SHELL_SCRIPT" == *"\${TARGET_ENV}"* ]]; then
    SCRIPT_HAS_VAR="true"
fi

# 3. Functional Test (Anti-Gaming)
# Trigger a build with the specific parameter and check output
echo "Triggering verification build with TARGET_ENV=$TEST_ENV_VAL..."

# We use the CLI to build and wait (-s) and stream output (-v)
# We capture this output to a file
VERIFICATION_BUILD_LOG="/tmp/verification_build.log"
jenkins_cli build "$JOB_NAME" -p "TARGET_ENV=$TEST_ENV_VAL" -s -v > "$VERIFICATION_BUILD_LOG" 2>&1

# Read the log
BUILD_OUTPUT=$(cat "$VERIFICATION_BUILD_LOG")
echo "Verification Build Output snippet:"
head -n 20 "$VERIFICATION_BUILD_LOG"

# Check if the output contains the expected dynamic string
# Expected: "Deploying service to staging environment..."
EXPECTED_STRING="Deploying service to $TEST_ENV_VAL environment"
OUTPUT_CORRECT="false"
if grep -Fq "$EXPECTED_STRING" "$VERIFICATION_BUILD_LOG"; then
    OUTPUT_CORRECT="true"
fi

# Check if build succeeded
BUILD_SUCCESS="false"
if grep -q "SUCCESS" "$VERIFICATION_BUILD_LOG"; then
    BUILD_SUCCESS="true"
fi

# 4. Final Screenshot
take_screenshot /tmp/task_end_screenshot.png

# 5. Export JSON
# Use jq to safely construct JSON
jq -n \
    --arg job_name "$JOB_NAME" \
    --arg param_name "$PARAM_NAME_FOUND" \
    --arg param_type "$PARAM_TYPE_FOUND" \
    --arg param_choices "$PARAM_CHOICES_FOUND" \
    --arg script_content "$SHELL_SCRIPT" \
    --argjson script_has_var "$SCRIPT_HAS_VAR" \
    --arg test_val "$TEST_ENV_VAL" \
    --argjson output_correct "$OUTPUT_CORRECT" \
    --argjson build_success "$BUILD_SUCCESS" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        job_exists: true,
        config: {
            param_name: $param_name,
            param_type: $param_type,
            choices_csv: $param_choices,
            script_has_variable: $script_has_var,
            script_raw: $script_content
        },
        functional_test: {
            parameter_used: $test_val,
            output_correct: $output_correct,
            build_success: $build_success
        },
        timestamp: $timestamp
    }' > "$EXPORT_FILE"

# Make readable
chmod 666 "$EXPORT_FILE" 2>/dev/null || true

echo "Export complete. Result:"
cat "$EXPORT_FILE"