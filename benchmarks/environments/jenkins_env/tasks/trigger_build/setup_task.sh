#!/bin/bash
# Setup script for Trigger Build task
# Creates a test job that can be built

echo "=== Setting up Trigger Build Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Jenkins API to be ready
echo "Waiting for Jenkins API..."
if ! wait_for_jenkins_api 60; then
    echo "WARNING: Jenkins API not ready"
fi

# Record initial build count
echo "Recording initial state..."
INITIAL_JOB_COUNT=$(count_jobs)
printf '%s' "$INITIAL_JOB_COUNT" > /tmp/initial_trigger_job_count

# Create a simple test job that the agent can build
TEST_JOB_NAME="Test-Build-Job"
echo "Creating test job '$TEST_JOB_NAME' for agent to trigger..."

# Create job config XML
cat > /tmp/test_job_config.xml << 'JOBXML'
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>A simple test job for triggering builds</description>
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
      <command>echo &quot;Build triggered successfully!&quot;
echo &quot;Build number: $BUILD_NUMBER&quot;
echo &quot;Build ID: $BUILD_ID&quot;
sleep 2
echo &quot;Build completed!&quot;</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
JOBXML

# Create the job using REST API with proper CSRF cookie handling
echo "Creating job via REST API..."

# Get CSRF crumb WITH cookie jar (required for Jenkins CSRF protection)
CRUMB_JSON=$(curl -s -u "$JENKINS_USER:$JENKINS_PASS" -c /tmp/jenkins_cookies "$JENKINS_URL/crumbIssuer/api/json" 2>/dev/null || echo "{}")
CRUMB_FIELD=$(echo "$CRUMB_JSON" | jq -r '.crumbRequestField // empty' 2>/dev/null)
CRUMB_VALUE=$(echo "$CRUMB_JSON" | jq -r '.crumb // empty' 2>/dev/null)
echo "CSRF crumb field: $CRUMB_FIELD"

# Create job via REST API with cookie jar
if [ -n "$CRUMB_FIELD" ] && [ -n "$CRUMB_VALUE" ]; then
    HTTP_CODE=$(curl -s -o /tmp/create_job.log -w "%{http_code}" \
        -u "$JENKINS_USER:$JENKINS_PASS" \
        -b /tmp/jenkins_cookies \
        -X POST "$JENKINS_URL/createItem?name=$TEST_JOB_NAME" \
        -H "Content-Type: text/xml" \
        -H "$CRUMB_FIELD: $CRUMB_VALUE" \
        --data-binary @/tmp/test_job_config.xml 2>/dev/null)
else
    # Fallback: try without CSRF (in case it's disabled)
    HTTP_CODE=$(curl -s -o /tmp/create_job.log -w "%{http_code}" \
        -u "$JENKINS_USER:$JENKINS_PASS" \
        -X POST "$JENKINS_URL/createItem?name=$TEST_JOB_NAME" \
        -H "Content-Type: text/xml" \
        --data-binary @/tmp/test_job_config.xml 2>/dev/null)
fi

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    echo "Test job created successfully! (HTTP $HTTP_CODE)"
else
    echo "WARNING: REST API creation returned HTTP $HTTP_CODE, trying CLI..."
    cat /tmp/create_job.log 2>/dev/null || true
    # Fallback to CLI jar
    if [ -f /tmp/jenkins-cli.jar ]; then
        java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" create-job "$TEST_JOB_NAME" < /tmp/test_job_config.xml 2>&1 || true
    fi
fi

# Verify job exists
sleep 2
if job_exists "$TEST_JOB_NAME"; then
    echo "Verified: Job '$TEST_JOB_NAME' exists in Jenkins"
else
    echo "ERROR: Job '$TEST_JOB_NAME' was not created!"
fi

# Record that no builds have been run yet
printf '%s' "0" > /tmp/initial_build_count

# Clean up temp file
rm -f /tmp/test_job_config.xml

# Ensure Firefox is running and focused on Jenkins
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    DISPLAY=:1 firefox "$JENKINS_URL" > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|jenkins" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox window and navigate to Jenkins home
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Trigger Build Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Click on 'Test-Build-Job' on the Jenkins dashboard"
echo ""
echo "  2. Trigger a build:"
echo "     - Click 'Build Now' in the left sidebar"
echo ""
echo "  3. Wait for the build to complete"
echo "     - The build should complete quickly (takes ~2-3 seconds)"
echo "     - Look for green checkmark or 'Success' status in Build History"
echo ""
