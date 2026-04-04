#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up copy_customize_job task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Wait for Jenkins API to be fully ready
echo "Waiting for Jenkins API..."
wait_for_jenkins_api 60

# Record initial job count
INITIAL_COUNT=$(count_jobs)
echo "$INITIAL_COUNT" > /tmp/initial_job_count.txt

# Cleanup: Remove target job if it exists (from previous runs)
if job_exists "Regression-Test-Runner"; then
    echo "Cleaning up stale Regression-Test-Runner job..."
    jenkins_cli delete-job "Regression-Test-Runner" 2>/dev/null || true
fi

# Cleanup: Remove source job to ensure clean state
if job_exists "Smoke-Test-Runner"; then
    echo "Cleaning up stale Smoke-Test-Runner job..."
    jenkins_cli delete-job "Smoke-Test-Runner" 2>/dev/null || true
fi

# Create the Source Job "Smoke-Test-Runner" via CLI
echo "Creating source job: Smoke-Test-Runner..."
cat <<'JOBXML' | jenkins_cli create-job "Smoke-Test-Runner"
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Runs smoke tests against staging environment</description>
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
      <command>echo "Running smoke tests..." &amp;&amp; echo "TEST_SUITE=smoke" &amp;&amp; echo "TARGET_ENV=staging" &amp;&amp; sleep 2 &amp;&amp; echo "Smoke tests passed: 15/15"</command>
      <configuredLocalRules/>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
JOBXML

# Verify setup
if job_exists "Smoke-Test-Runner"; then
    echo "Verified: Smoke-Test-Runner created successfully."
else
    echo "ERROR: Failed to create Smoke-Test-Runner."
    exit 1
fi

# Ensure Firefox is open to the dashboard
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$JENKINS_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Refresh Firefox to show the new job
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 xdotool key F5
    sleep 2
    # Ensure maximized
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="