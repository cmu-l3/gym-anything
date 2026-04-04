#!/bin/bash
# Setup script for Deprecate Jenkins Job task
# Creates a failing legacy job that needs to be disabled

echo "=== Setting up Deprecate Jenkins Job Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Jenkins API to be ready
echo "Waiting for Jenkins API..."
if ! wait_for_jenkins_api 60; then
    echo "WARNING: Jenkins API not ready"
fi

JOB_NAME="Legacy-Ecommerce-Monolith"
echo "Creating legacy job '$JOB_NAME'..."

# Create job config XML (Failing job)
cat > /tmp/legacy_job_config.xml << 'JOBXML'
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Builds the monolith ecommerce application. Maintained by the core team.</description>
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
      <command>echo "Building Legacy Monolith..."
echo "Error: Out of memory during compilation."
echo "Build failed."
exit 1</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
JOBXML

# Create the job using REST API
# Get CSRF crumb
CRUMB_JSON=$(curl -s -u "$JENKINS_USER:$JENKINS_PASS" -c /tmp/jenkins_cookies "$JENKINS_URL/crumbIssuer/api/json" 2>/dev/null || echo "{}")
CRUMB_FIELD=$(echo "$CRUMB_JSON" | jq -r '.crumbRequestField // empty' 2>/dev/null)
CRUMB_VALUE=$(echo "$CRUMB_JSON" | jq -r '.crumb // empty' 2>/dev/null)

if [ -n "$CRUMB_FIELD" ] && [ -n "$CRUMB_VALUE" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "$JENKINS_USER:$JENKINS_PASS" \
        -b /tmp/jenkins_cookies \
        -X POST "$JENKINS_URL/createItem?name=$JOB_NAME" \
        -H "Content-Type: text/xml" \
        -H "$CRUMB_FIELD: $CRUMB_VALUE" \
        --data-binary @/tmp/legacy_job_config.xml 2>/dev/null)
else
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "$JENKINS_USER:$JENKINS_PASS" \
        -X POST "$JENKINS_URL/createItem?name=$JOB_NAME" \
        -H "Content-Type: text/xml" \
        --data-binary @/tmp/legacy_job_config.xml 2>/dev/null)
fi

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    echo "Job '$JOB_NAME' created successfully."
else
    echo "WARNING: Job creation returned HTTP $HTTP_CODE"
    # Fallback to CLI
    jenkins_cli create-job "$JOB_NAME" < /tmp/legacy_job_config.xml 2>/dev/null || true
fi

# Trigger a build so it has history and shows as failed (Red)
echo "Triggering initial failure build..."
jenkins_cli build "$JOB_NAME" -w || true

# Verify setup
if job_exists "$JOB_NAME"; then
    echo "Verified: Job '$JOB_NAME' exists"
else
    echo "ERROR: Job '$JOB_NAME' was not created!"
fi

# Ensure Firefox is running and open to the job page
echo "Ensuring Firefox is running..."
JOB_URL="$JENKINS_URL/job/$JOB_NAME"
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    DISPLAY=:1 firefox "$JOB_URL" > /tmp/firefox_task.log 2>&1 &
    sleep 5
else
    # Navigate existing firefox
    DISPLAY=:1 firefox "$JOB_URL" &
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|jenkins" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Deprecate Job Task Setup Complete ==="