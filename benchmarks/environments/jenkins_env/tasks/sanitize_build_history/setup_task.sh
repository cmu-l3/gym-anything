#!/bin/bash
# Setup script for Sanitize Build History task
# Creates a job and generates 6 builds, injecting "leaked secrets" into #2 and #4

echo "=== Setting up Sanitize Build History Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Jenkins API to be ready
echo "Waiting for Jenkins API..."
if ! wait_for_jenkins_api 60; then
    echo "WARNING: Jenkins API not ready"
fi

JOB_NAME="payment-gateway-ci"

# Check if job exists and delete it to ensure clean state
if job_exists "$JOB_NAME"; then
    echo "Deleting existing job '$JOB_NAME'..."
    java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" delete-job "$JOB_NAME"
fi

# Create job config with a shell step that simulates leaked secrets based on BUILD_NUMBER
cat > /tmp/sanitize_job_config.xml << 'JOBXML'
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>CI pipeline for Payment Gateway. WARNING: Some builds contain leaked credentials.</description>
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
      <command>
echo "Starting build process..."
echo "Compiling source code..."
sleep 1

if [ "$BUILD_NUMBER" -eq "2" ] || [ "$BUILD_NUMBER" -eq "4" ]; then
    echo "Connecting to database..."
    echo "[CRITICAL] DB_PASSWORD=s3cr3t_p@ssw0rd_LEAKED_VALUE"
    echo "Migration failed."
    exit 1
else
    echo "Unit tests passed."
    echo "Packaging artifact..."
fi

echo "Build complete."
      </command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
JOBXML

echo "Creating job '$JOB_NAME'..."
# Create job via CLI
java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" create-job "$JOB_NAME" < /tmp/sanitize_job_config.xml

# Trigger 6 builds sequentially
echo "Triggering 6 builds..."
for i in {1..6}; do
    echo "  Triggering build #$i..."
    # Build and wait for completion (-s)
    java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" build "$JOB_NAME" -s
    sleep 1
done

# Verify state
COUNT=$(jenkins_api "job/${JOB_NAME}/api/json" | jq -r '.builds | length')
echo "Created $COUNT builds for $JOB_NAME"

# Clean up temp config
rm -f /tmp/sanitize_job_config.xml

# Ensure Firefox is running and focused on the job page
echo "Ensuring Firefox is running..."
JOB_URL="$JENKINS_URL/job/$JOB_NAME"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    DISPLAY=:1 firefox "$JOB_URL" > /tmp/firefox_task.log 2>&1 &
    sleep 5
else
    # Navigate existing firefox
    DISPLAY=:1 firefox -new-tab "$JOB_URL" &
    sleep 2
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|jenkins" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Record start time for verification
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="