#!/bin/bash
# Setup script for Configure Log Rotation task
# Creates 3 jobs and populates them with build history

echo "=== Setting up Configure Log Rotation Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Jenkins API to be ready
echo "Waiting for Jenkins API..."
if ! wait_for_jenkins_api 60; then
    echo "WARNING: Jenkins API not ready"
fi

# Define jobs to create
JOBS=("nightly-integration-tests" "feature-branch-builds" "release-pipeline")

# Create jobs
for JOB_NAME in "${JOBS[@]}"; do
    echo "Creating job '$JOB_NAME'..."
    
    # Create simple config XML (no log rotation initially)
    cat > "/tmp/${JOB_NAME}_config.xml" << JOBXML
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Task job: $JOB_NAME</description>
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
      <command>echo "Building $JOB_NAME..."
date
sleep 0.5</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
JOBXML

    # Create job via CLI
    jenkins_cli create-job "$JOB_NAME" < "/tmp/${JOB_NAME}_config.xml"
    
    # Trigger builds to create history (12 builds each)
    echo "Triggering build history for $JOB_NAME..."
    for i in {1..12}; do
        jenkins_cli build "$JOB_NAME" -w > /dev/null 2>&1 &
        # Small stagger to prevent queue jam
        sleep 0.2
    done
done

echo "Waiting for builds to complete..."
# Give some time for builds to finish
sleep 15

# Record initial state (Hash of config.xml)
echo "Recording initial configuration state..."
mkdir -p /tmp/task_initial_state
for JOB_NAME in "${JOBS[@]}"; do
    CONFIG=$(get_job_config "$JOB_NAME")
    echo "$CONFIG" | md5sum | awk '{print $1}' > "/tmp/task_initial_state/${JOB_NAME}_hash.txt"
    
    # Count builds
    COUNT=$(jenkins_api "job/$JOB_NAME/api/json" | jq '.builds | length')
    echo "$COUNT" > "/tmp/task_initial_state/${JOB_NAME}_count.txt"
    echo "  $JOB_NAME: $COUNT builds, Hash: $(cat /tmp/task_initial_state/${JOB_NAME}_hash.txt)"
done

# Ensure Firefox is running and focused on Jenkins dashboard
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    DISPLAY=:1 firefox "$JENKINS_URL" > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

# Wait for Firefox window
wait_for_window "firefox\|mozilla\|jenkins" 30

# Focus Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="