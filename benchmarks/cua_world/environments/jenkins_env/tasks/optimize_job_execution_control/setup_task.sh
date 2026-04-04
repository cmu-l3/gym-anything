#!/bin/bash
# Setup script for Optimize Job Execution Control task
# Creates a job with concurrency ENABLED and NO quiet period

echo "=== Setting up Optimize Job Execution Control Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Jenkins API to be ready
echo "Waiting for Jenkins API..."
if ! wait_for_jenkins_api 60; then
    echo "WARNING: Jenkins API not ready"
fi

JOB_NAME="Docs-Site-Gen"
echo "Creating job '$JOB_NAME'..."

# Create job config XML
# concurrentBuild = true (Bad state, needs to be false)
# No quietPeriod set (uses system default)
cat > /tmp/docs_job_config.xml << 'JOBXML'
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Generates static documentation site. currently misconfigured allowing race conditions.</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <scm class="hudson.scm.NullSCM"/>
  <canRoam>true</canRoam>
  <disabled>false</disabled>
  <blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>
  <blockBuildWhenUpstreamBuilding>false</blockBuildWhenUpstreamBuilding>
  <triggers/>
  <concurrentBuild>true</concurrentBuild>
  <builders>
    <hudson.tasks.Shell>
      <command>echo "Generating docs site..."
sleep 5
echo "Done."</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
JOBXML

# Create the job using CLI (reliable)
if [ -f /tmp/jenkins-cli.jar ]; then
    java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" create-job "$JOB_NAME" < /tmp/docs_job_config.xml
else
    # Fallback to curl
    # Get CSRF crumb
    CRUMB_JSON=$(curl -s -u "$JENKINS_USER:$JENKINS_PASS" -c /tmp/jenkins_cookies "$JENKINS_URL/crumbIssuer/api/json" 2>/dev/null || echo "{}")
    CRUMB_FIELD=$(echo "$CRUMB_JSON" | jq -r '.crumbRequestField // empty' 2>/dev/null)
    CRUMB_VALUE=$(echo "$CRUMB_JSON" | jq -r '.crumb // empty' 2>/dev/null)

    if [ -n "$CRUMB_FIELD" ] && [ -n "$CRUMB_VALUE" ]; then
        curl -s -X POST "$JENKINS_URL/createItem?name=$JOB_NAME" \
            -u "$JENKINS_USER:$JENKINS_PASS" \
            -b /tmp/jenkins_cookies \
            -H "Content-Type: text/xml" \
            -H "$CRUMB_FIELD: $CRUMB_VALUE" \
            --data-binary @/tmp/docs_job_config.xml
    else
        curl -s -X POST "$JENKINS_URL/createItem?name=$JOB_NAME" \
            -u "$JENKINS_USER:$JENKINS_PASS" \
            -H "Content-Type: text/xml" \
            --data-binary @/tmp/docs_job_config.xml
    fi
fi

rm -f /tmp/docs_job_config.xml

# Verify job creation
if job_exists "$JOB_NAME"; then
    echo "Job '$JOB_NAME' created successfully."
else
    echo "ERROR: Failed to create job '$JOB_NAME'"
    exit 1
fi

# Ensure Firefox is running and focused
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox "$JENKINS_URL/job/$JOB_NAME" > /tmp/firefox_task.log 2>&1 &
    sleep 5
else
    # Navigate existing firefox
    DISPLAY=:1 firefox "$JENKINS_URL/job/$JOB_NAME" &
fi

if wait_for_window "firefox\|mozilla\|jenkins" 30; then
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="