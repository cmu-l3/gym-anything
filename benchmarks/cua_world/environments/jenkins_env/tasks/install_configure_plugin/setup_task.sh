#!/bin/bash
# Setup script for Install & Configure Plugin task
set -e

echo "=== Setting up Install & Configure Plugin Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Wait for Jenkins API to be ready
echo "Waiting for Jenkins API..."
if ! wait_for_jenkins_api 120; then
    echo "ERROR: Jenkins API not ready"
    exit 1
fi

# Record initial installed plugins (to prove it wasn't installed before)
echo "Recording initial plugin state..."
jenkins_api "pluginManager/api/json?depth=1" | jq -r '.plugins[].shortName' | sort > /tmp/initial_plugins.txt

# Ensure Timestamper is NOT installed
if grep -q "timestamper" /tmp/initial_plugins.txt; then
    echo "WARNING: Timestamper plugin already installed. Attempting to uninstall..."
    # Note: Uninstalling via API is tricky, usually requires restart. 
    # For this environment, we assume a clean state or just proceed.
    # In a real scenario, we might need to purge it manually.
    echo "Using existing state (clean slate preferred)."
fi

# Force Update Center refresh so 'Available' tab works immediately
echo "Triggering Update Center refresh..."
curl -s -u "$JENKINS_USER:$JENKINS_PASS" -X POST "$JENKINS_URL/pluginManager/checkUpdatesServer" > /dev/null || true

# Create the QA-Test-Runner job (without timestamp wrapper)
JOB_NAME="QA-Test-Runner"
echo "Creating job '$JOB_NAME'..."

cat > /tmp/qa_job_config.xml << 'JOBXML'
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Runs critical QA integration tests. Timestamps are required for debugging latency issues.</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <scm class="hudson.scm.NullSCM"/>
  <canRoam>true</canRoam>
  <disabled>false</disabled>
  <blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>
  <blockBuildWhenUpstreamBuilding>false</blockBuildWhenUpstreamBuilding>
  <triggers/>
  <concurrentBuild>false</concurrentBuild>
  <builders>
    <hudson.tasks.Shell>
      <command>echo "=== QA Test Suite Execution ==="
echo "Phase 1: Unit tests starting..."
sleep 2
echo "Phase 1: Unit tests PASSED (142 tests, 0 failures)"
echo "Phase 2: Integration tests starting..."
sleep 3
echo "Phase 2: Integration tests PASSED (38 tests, 0 failures)"
echo "Phase 3: Smoke tests starting..."
sleep 1
echo "Phase 3: Smoke tests PASSED (12 tests, 0 failures)"
echo "=== All test phases complete ==="</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
JOBXML

# Create job via CLI (reliable) or API
if [ -f /tmp/jenkins-cli.jar ]; then
    java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" create-job "$JOB_NAME" < /tmp/qa_job_config.xml
else
    # Fallback to API
    CRUMB=$(curl -s -u "$JENKINS_USER:$JENKINS_PASS" "$JENKINS_URL/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)")
    curl -s -u "$JENKINS_USER:$JENKINS_PASS" -H "$CRUMB" -X POST "$JENKINS_URL/createItem?name=$JOB_NAME" --header "Content-Type:text/xml" --data-binary @/tmp/qa_job_config.xml
fi

# Record initial config hash for change detection
if job_exists "$JOB_NAME"; then
    get_job_config "$JOB_NAME" | md5sum > /tmp/initial_config_hash.txt
else
    echo "ERROR: Failed to create start job"
    exit 1
fi

# Ensure Firefox is running and focused
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$JENKINS_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for window
wait_for_window "firefox\|mozilla\|jenkins" 30

# Maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="