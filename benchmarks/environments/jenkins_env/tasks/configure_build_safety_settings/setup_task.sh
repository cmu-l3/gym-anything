#!/bin/bash
# Setup script for Configure Build Safety Settings task
# Creates two jobs: Backend-Build and Production-Deploy
# Production-Deploy starts in an "unsafe" state (concurrent allowed, no quiet period, no blocking)

echo "=== Setting up Configure Build Safety Settings Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Jenkins API to be ready
echo "Waiting for Jenkins API..."
if ! wait_for_jenkins_api 60; then
    echo "WARNING: Jenkins API not ready"
fi

# 1. Create Upstream Job: Backend-Build
echo "Creating upstream job 'Backend-Build'..."
cat > /tmp/backend_config.xml << 'EOF'
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <actions/>
  <description>Compiles the backend artifacts.</description>
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
      <command>echo "Compiling backend..."
sleep 5</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
EOF
jenkins_cli create-job Backend-Build < /tmp/backend_config.xml

# 2. Create Downstream Job: Production-Deploy
# Intentionally configured with "Unsafe" settings:
# - concurrentBuild: true (Allowed)
# - quietPeriod: null/default (0)
# - blockBuildWhenUpstreamBuilding: false
echo "Creating downstream job 'Production-Deploy'..."
cat > /tmp/deploy_config.xml << 'EOF'
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <actions/>
  <description>Deploys artifacts to production environment.</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <scm class="hudson.scm.NullSCM"/>
  <canRoam>true</canRoam>
  <disabled>false</disabled>
  <blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>
  <blockBuildWhenUpstreamBuilding>false</blockBuildWhenUpstreamBuilding>
  <triggers>
    <jenkins.triggers.ReverseBuildTrigger>
      <spec></spec>
      <upstreamProjects>Backend-Build</upstreamProjects>
      <threshold>
        <name>SUCCESS</name>
        <ordinal>0</ordinal>
        <color>BLUE</color>
        <completeBuild>true</completeBuild>
      </threshold>
    </jenkins.triggers.ReverseBuildTrigger>
  </triggers>
  <concurrentBuild>true</concurrentBuild>
  <builders>
    <hudson.tasks.Shell>
      <command>echo "Deploying to production..."
sleep 2</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
EOF
jenkins_cli create-job Production-Deploy < /tmp/deploy_config.xml

# Verify jobs creation
if job_exists "Production-Deploy" && job_exists "Backend-Build"; then
    echo "Jobs created successfully."
else
    echo "ERROR: Failed to create jobs."
    exit 1
fi

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
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="