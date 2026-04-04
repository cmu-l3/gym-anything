#!/bin/bash
# Setup script for Configure Build Schedule task
# Creates a job without any build triggers, agent must add cron schedule

echo "=== Setting up Configure Build Schedule Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Jenkins API to be ready
echo "Waiting for Jenkins API..."
if ! wait_for_jenkins_api 60; then
    echo "WARNING: Jenkins API not ready"
fi

# Create a freestyle job without any triggers
JOB_NAME="Nightly-Backup"
echo "Creating job '$JOB_NAME' without build triggers..."

cat > /tmp/schedule_job_config.xml << 'JOBXML'
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Nightly backup job - needs periodic build trigger configured</description>
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
      <command>echo "Running nightly backup..."
echo "Backup started at $(date)"
sleep 1
echo "Backup completed successfully!"</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
JOBXML

# Create the job using REST API with CSRF cookie handling
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
        --data-binary @/tmp/schedule_job_config.xml 2>/dev/null)
else
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "$JENKINS_USER:$JENKINS_PASS" \
        -X POST "$JENKINS_URL/createItem?name=$JOB_NAME" \
        -H "Content-Type: text/xml" \
        --data-binary @/tmp/schedule_job_config.xml 2>/dev/null)
fi

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    echo "Job '$JOB_NAME' created successfully! (HTTP $HTTP_CODE)"
else
    echo "WARNING: Job creation returned HTTP $HTTP_CODE"
fi

# Verify job exists and has NO triggers
sleep 2
if job_exists "$JOB_NAME"; then
    echo "Verified: Job '$JOB_NAME' exists in Jenkins"
    CONFIG=$(get_job_config "$JOB_NAME" 2>/dev/null)
    TRIGGER_CHECK=$(echo "$CONFIG" | grep -c "TimerTrigger" || true)
    echo "Current trigger count: $TRIGGER_CHECK (should be 0)"
else
    echo "ERROR: Job '$JOB_NAME' was not created!"
fi

rm -f /tmp/schedule_job_config.xml

# Ensure Firefox is running and focused on Jenkins dashboard
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    DISPLAY=:1 firefox "$JENKINS_URL" > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

if ! wait_for_window "firefox\|mozilla\|jenkins" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Configure Build Schedule Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Open the 'Nightly-Backup' job from the dashboard"
echo ""
echo "  2. Click 'Configure' to open job settings"
echo ""
echo "  3. Add a periodic build trigger:"
echo "     - Scroll to 'Build Triggers' section"
echo "     - Check 'Build periodically'"
echo "     - Enter schedule: H 0 * * *"
echo ""
echo "  4. Save the configuration"
echo ""
