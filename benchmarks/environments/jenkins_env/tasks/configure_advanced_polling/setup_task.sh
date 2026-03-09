#!/bin/bash
# Setup script for Configure Advanced Polling task

echo "=== Setting up Configure Advanced Polling Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Jenkins API to be ready
echo "Waiting for Jenkins API..."
if ! wait_for_jenkins_api 60; then
    echo "WARNING: Jenkins API not ready"
fi

# Job parameters
JOB_NAME="legacy-inventory-sync"

# Define job XML (Freestyle project with NO triggers and default quiet period)
cat > /tmp/inventory_job_config.xml << 'JOBXML'
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Syncs legacy inventory data. Requires polling configuration.</description>
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
      <command>echo "Syncing inventory..."
sleep 2
echo "Sync complete."</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
JOBXML

echo "Creating job '$JOB_NAME'..."

# Create the job using Jenkins CLI (more reliable for XML injection than curl sometimes)
if [ ! -f /tmp/jenkins-cli.jar ]; then
    curl -s "$JENKINS_URL/jnlpJars/jenkins-cli.jar" -o /tmp/jenkins-cli.jar
fi

java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" create-job "$JOB_NAME" < /tmp/inventory_job_config.xml

# Verify job creation
if job_exists "$JOB_NAME"; then
    echo "Job '$JOB_NAME' created successfully."
else
    echo "ERROR: Failed to create job '$JOB_NAME'"
    exit 1
fi

# Clean up
rm -f /tmp/inventory_job_config.xml

# Record start time
date +%s > /tmp/task_start_time.txt

# Record initial configuration hash to detect changes later
get_job_config "$JOB_NAME" | md5sum > /tmp/initial_config_hash.txt

# Ensure Firefox is running and focused on Jenkins
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    DISPLAY=:1 firefox "$JENKINS_URL/job/$JOB_NAME/configure" > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

# Wait for Firefox window
wait_for_window "firefox\|mozilla\|jenkins" 30

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="