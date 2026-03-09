#!/bin/bash
set -e
echo "=== Setting up task: configure_global_env_vars ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Jenkins API to be accessible
echo "Waiting for Jenkins API..."
wait_for_jenkins_api 60

# Verify no global environment variables are currently set
# (Clean state — remove any that might exist from previous runs to ensure accurate verification)
echo "Ensuring clean global environment variable state..."
curl -s -u "$JENKINS_USER:$JENKINS_PASS" \
    -d 'script=
import hudson.slaves.EnvironmentVariablesNodeProperty
def instance = Jenkins.instance
def props = instance.globalNodeProperties
def envProps = props.getAll(EnvironmentVariablesNodeProperty.class)
envProps.each { props.remove(it) }
instance.save()
println("Cleared global env vars")
' "$JENKINS_URL/scriptText" 2>/dev/null || echo "WARNING: Could not clear env vars"

# Delete the verification job if it exists from a previous run
echo "Cleaning up any existing verification job..."
if job_exists "EnvVar-Verification-Job"; then
    # Use CLI to delete job safely
    if [ -f /tmp/jenkins-cli.jar ]; then
        java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" delete-job "EnvVar-Verification-Job" 2>/dev/null || true
    else
        # Fallback to API
        curl -X POST -u "$JENKINS_USER:$JENKINS_PASS" "$JENKINS_URL/job/EnvVar-Verification-Job/doDelete" 2>/dev/null || true
    fi
    echo "Deleted existing EnvVar-Verification-Job"
fi

# Record initial state
INITIAL_JOB_COUNT=$(count_jobs)
echo "$INITIAL_JOB_COUNT" > /tmp/initial_job_count.txt
echo "Initial job count: $INITIAL_JOB_COUNT"

# Verify initial state: no global env vars
INITIAL_ENV_CHECK=$(curl -s -u "$JENKINS_USER:$JENKINS_PASS" \
    -d 'script=
import hudson.slaves.EnvironmentVariablesNodeProperty
def props = Jenkins.instance.globalNodeProperties.getAll(EnvironmentVariablesNodeProperty.class)
def count = 0
props.each { p -> count += p.envVars.size() }
println(count)
' "$JENKINS_URL/scriptText" 2>/dev/null || echo "0")
echo "Initial global env var count: $INITIAL_ENV_CHECK"
echo "$INITIAL_ENV_CHECK" > /tmp/initial_env_var_count.txt

# Ensure Firefox is running and navigate to Jenkins dashboard
echo "Navigating Firefox to Jenkins dashboard..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$JENKINS_URL' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Wait for window
wait_for_window "firefox\|mozilla\|jenkins" 30

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    sleep 1
    # Ensure on Dashboard
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8080/"
    DISPLAY=:1 xdotool key Return
    sleep 3
    
    # Maximize
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="