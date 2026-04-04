#!/bin/bash
set -e
echo "=== Setting up configure_builtin_node task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Jenkins API
if ! wait_for_jenkins_api 60; then
    echo "WARNING: Jenkins API not ready"
fi

# Ensure no pre-existing job with the target name
echo "Cleaning up any existing target job..."
if job_exists "controller-health-check"; then
    jenkins_cli delete-job controller-health-check 2>/dev/null || true
fi

# Reset built-in node to default state (2 executors, NORMAL mode, no labels)
# We use a Groovy script via CLI to ensure clean state
echo "Resetting built-in node configuration..."
cat > /tmp/reset_node.groovy << 'GROOVY'
import jenkins.model.Jenkins
import hudson.model.Node.Mode

def jenkins = Jenkins.get()
// Set to default 2 executors
jenkins.setNumExecutors(2)
// Set mode to Use this node as much as possible (NORMAL)
jenkins.setMode(Mode.NORMAL)
// Clear labels
jenkins.setLabelString("")
jenkins.save()
println "Built-in node reset complete"
GROOVY

# Execute reset script
java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" groovy = < /tmp/reset_node.groovy

# Record initial state for anti-gaming detection
INITIAL_EXECUTORS=$(jenkins_api "computer/(built-in)/api/json" 2>/dev/null | jq -r '.numExecutors // "unknown"')
INITIAL_MODE=$(jenkins_api "computer/(built-in)/api/json" 2>/dev/null | jq -r '.mode // "unknown"')
INITIAL_JOB_EXISTS="false"

cat > /tmp/initial_state.json << EOF
{
  "initial_executors": "$INITIAL_EXECUTORS",
  "initial_mode": "$INITIAL_MODE",
  "initial_job_exists": "$INITIAL_JOB_EXISTS",
  "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded: Executors=$INITIAL_EXECUTORS, Mode=$INITIAL_MODE"

# Ensure Firefox is open to Jenkins dashboard
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$JENKINS_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for window and maximize
if wait_for_window "firefox\|mozilla\|jenkins" 30; then
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="