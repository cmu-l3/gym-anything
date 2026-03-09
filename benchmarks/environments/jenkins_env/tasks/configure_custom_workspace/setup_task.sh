#!/bin/bash
# Setup script for Configure Custom Workspace task
# Creates a legacy job with default workspace configuration

echo "=== Setting up Configure Custom Workspace Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Jenkins API to be ready
echo "Waiting for Jenkins API..."
if ! wait_for_jenkins_api 60; then
    echo "WARNING: Jenkins API not ready"
fi

# Clean up any previous state
rm -rf /tmp/legacy_ws
JOB_NAME="legacy-system-build"

# Delete job if it exists (to ensure clean state)
if job_exists "$JOB_NAME"; then
    echo "Removing existing job..."
    java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" delete-job "$JOB_NAME" 2>/dev/null || true
fi

# Create the job configuration XML (Standard Git job, default workspace)
cat > /tmp/legacy_job_config.xml << 'JOBXML'
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Legacy system build - requires custom workspace configuration.</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <scm class="hudson.plugins.git.GitSCM">
    <configVersion>2</configVersion>
    <userRemoteConfigs>
      <hudson.plugins.git.UserRemoteConfig>
        <url>https://github.com/jenkins-docs/simple-java-maven-app.git</url>
      </hudson.plugins.git.UserRemoteConfig>
    </userRemoteConfigs>
    <branches>
      <hudson.plugins.git.BranchSpec>
        <name>*/master</name>
      </hudson.plugins.git.BranchSpec>
    </branches>
    <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
    <submoduleCfg class="list"/>
    <extensions/>
  </scm>
  <canRoam>true</canRoam>
  <disabled>false</disabled>
  <blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>
  <blockBuildWhenUpstreamBuilding>false</blockBuildWhenUpstreamBuilding>
  <triggers/>
  <concurrentBuild>false</concurrentBuild>
  <builders>
    <hudson.tasks.Shell>
      <command>echo "Listing workspace contents:"
ls -la
echo "Build complete."</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
JOBXML

# Create the job via CLI
echo "Creating job '$JOB_NAME'..."
if [ ! -f /tmp/jenkins-cli.jar ]; then
    curl -s "$JENKINS_URL/jnlpJars/jenkins-cli.jar" -o /tmp/jenkins-cli.jar
fi

java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" create-job "$JOB_NAME" < /tmp/legacy_job_config.xml

# Verify job creation
if job_exists "$JOB_NAME"; then
    echo "Job '$JOB_NAME' created successfully."
else
    echo "ERROR: Failed to create job '$JOB_NAME'"
    exit 1
fi

# Record initial build count (should be 0)
echo "0" > /tmp/initial_build_count

# Ensure Firefox is running and focused
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox "$JENKINS_URL/job/$JOB_NAME/configure" > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

# Focus Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="