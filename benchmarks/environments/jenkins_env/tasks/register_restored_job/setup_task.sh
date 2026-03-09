#!/bin/bash
# Setup script for Register Restored Job task
# Manually places a job on the filesystem but does NOT register it with Jenkins

echo "=== Setting up Register Restored Job Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time and initial system state for anti-gaming (restart detection)
date +%s > /tmp/task_start_time.txt

# Record the PID of the Jenkins process (java) inside the container
# This helps detect if the user restarted the service process
JENKINS_PID=$(docker exec jenkins-docker pgrep -f "jenkins.war" | head -1)
echo "$JENKINS_PID" > /tmp/initial_jenkins_pid.txt
echo "Initial Jenkins PID: $JENKINS_PID"

# Define the restored job directory
JENKINS_HOME="/home/ga/jenkins/jenkins_home"
JOB_DIR="$JENKINS_HOME/jobs/Legacy-Payroll"

# Verify Jenkins home exists
if [ ! -d "$JENKINS_HOME" ]; then
    echo "ERROR: Jenkins home directory not found at $JENKINS_HOME"
    exit 1
fi

# Create the job directory structure manually (simulating a file restore)
echo "Restoring 'Legacy-Payroll' job to filesystem..."
mkdir -p "$JOB_DIR"

# Create the job configuration XML
# A simple freestyle job that succeeds
cat > "$JOB_DIR/config.xml" << 'JOBXML'
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Legacy Payroll Processing System - Restored from Tape Backup</description>
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
      <command>echo "Starting payroll calculation..."
sleep 2
echo "Processing records..."
echo "Payroll run complete."
exit 0</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
JOBXML

# Set permissions to match Jenkins user (uid 1000)
# This is critical so Jenkins can read it when it eventually reloads
chown -R 1000:1000 "$JOB_DIR"
chmod 755 "$JOB_DIR"
chmod 644 "$JOB_DIR/config.xml"

echo "Job files placed at: $JOB_DIR"
echo "Note: Jenkins does not know about this job yet."

# Ensure Firefox is running and focused on Jenkins dashboard
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

# Focus Firefox window
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

echo "=== Setup Complete ==="
echo "Task: Make Jenkins see the 'Legacy-Payroll' job without restarting the server."