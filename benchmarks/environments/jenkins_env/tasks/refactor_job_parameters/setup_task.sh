#!/bin/bash
# Setup script for Refactor Job Parameters task
# Creates a hardcoded freestyle job that the agent must refactor

echo "=== Setting up Refactor Job Parameters Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Jenkins API
if ! wait_for_jenkins_api 60; then
    echo "WARNING: Jenkins API not ready"
fi

JOB_NAME="Deploy-Service"

# Define the initial hardcoded job XML
# It echoes a static string and has NO parameters
cat > /tmp/deploy_job_config.xml << 'JOBXML'
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Deploys the service to the target environment.</description>
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
      <command>echo "Deploying service to development environment..."</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
JOBXML

echo "Creating job '$JOB_NAME'..."

# Create the job using CLI (more robust for XML import)
jenkins_cli create-job "$JOB_NAME" < /tmp/deploy_job_config.xml

# Verify creation
if job_exists "$JOB_NAME"; then
    echo "Job '$JOB_NAME' created successfully."
else
    echo "ERROR: Failed to create job '$JOB_NAME'."
    exit 1
fi

rm -f /tmp/deploy_job_config.xml

# Ensure Firefox is open and focused on the job page
echo "Launching Firefox..."
JOB_URL="$JENKINS_URL/job/$JOB_NAME"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$JOB_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
else
    # Navigate existing firefox
    su - ga -c "DISPLAY=:1 firefox '$JOB_URL'"
fi

# Wait for window
wait_for_window "firefox\|mozilla" 30
focus_window "$(get_firefox_window_id)"
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="