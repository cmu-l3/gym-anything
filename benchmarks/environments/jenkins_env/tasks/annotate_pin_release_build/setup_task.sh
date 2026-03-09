#!/bin/bash
# Setup script for Annotate and Pin Release Build task
# Creates a job and generates 5 builds to simulate a history

echo "=== Setting up Annotate/Pin Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Jenkins API
echo "Waiting for Jenkins API..."
if ! wait_for_jenkins_api 60; then
    echo "WARNING: Jenkins API not ready"
    exit 1
fi

JOB_NAME="regression-test-suite"

# 1. Create the job configuration
# Simulates a test suite with realistic output
cat > /tmp/regression_job_config.xml << 'JOBXML'
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Automated regression test suite for main application.</description>
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
      <command>echo "=== Regression Test Suite ==="
echo "Running Module: Authentication Tests... 42 passed, 0 failed"
echo "Running Module: API Integration Tests... 87 passed, 0 failed"
echo "Running Module: Database Migration Tests... 23 passed, 0 failed"
echo "Running Module: UI Smoke Tests... 31 passed, 0 failed"
echo "=== Total: 183 tests passed, 0 failed ==="
sleep 1</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
JOBXML

# 2. Create the job
echo "Creating job '$JOB_NAME'..."
if ! job_exists "$JOB_NAME"; then
    # Use CLI for reliability
    if [ ! -f /tmp/jenkins-cli.jar ]; then
        curl -s "$JENKINS_URL/jnlpJars/jenkins-cli.jar" -o /tmp/jenkins-cli.jar
    fi
    java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" create-job "$JOB_NAME" < /tmp/regression_job_config.xml
else
    echo "Job already exists, cleaning up..."
    java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" delete-job "$JOB_NAME"
    java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" create-job "$JOB_NAME" < /tmp/regression_job_config.xml
fi

# 3. Trigger 5 builds
echo "Triggering 5 builds..."
for i in {1..5}; do
    echo "  Triggering build #$i..."
    java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" build "$JOB_NAME" -s
    # -s waits for completion, but strictly we just need them to queue and finish
    # sleep slightly to ensure ordering
    sleep 1
done

# 4. Verify builds exist
echo "Verifying build history..."
BUILD_COUNT=$(jenkins_api "job/$JOB_NAME/api/json" | jq '.builds | length')
echo "Current build count: $BUILD_COUNT"

if [ "$BUILD_COUNT" -lt 5 ]; then
    echo "WARNING: Expected 5 builds, found $BUILD_COUNT"
fi

# 5. Record initial state (to prove they were clean)
# We want to verify builds #1-#5 are NOT pinned and have NO description
jenkins_api "job/$JOB_NAME/api/json?depth=1" > /tmp/initial_build_state.json

# 6. Setup Firefox
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox "$JENKINS_URL/job/$JOB_NAME" > /tmp/firefox_task.log 2>&1 &
else
    # Navigate existing firefox
    DISPLAY=:1 firefox "$JENKINS_URL/job/$JOB_NAME" &
fi

# Wait for window and maximize
if wait_for_window "firefox\|mozilla\|jenkins" 30; then
    WID=$(get_firefox_window_id)
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 7. Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="