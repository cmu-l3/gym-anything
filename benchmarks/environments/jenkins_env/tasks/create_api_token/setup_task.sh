#!/bin/bash
# Setup script for Create API Token task
# 1. Ensures Jenkins is running
# 2. Creates sample jobs for the agent to list
# 3. Cleans up previous run artifacts

echo "=== Setting up Create API Token Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -f /home/ga/api_token.txt
rm -f /home/ga/jenkins_jobs.json

# Wait for Jenkins API to be ready
echo "Waiting for Jenkins API..."
if ! wait_for_jenkins_api 60; then
    echo "WARNING: Jenkins API not ready"
fi

# Ensure sample jobs exist
echo "Creating sample jobs..."
SAMPLE_JOBS=("backend-api-tests" "frontend-deploy" "database-migrations")

for job in "${SAMPLE_JOBS[@]}"; do
    if ! job_exists "$job"; then
        echo "Creating job: $job"
        # Create a simple freestyle job config
        cat <<EOF | java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" create-job "$job"
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Sample job for API testing: $job</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <scm class="hudson.scm.NullSCM"/>
  <canRoam>true</canRoam>
  <disabled>false</disabled>
  <blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>
  <blockBuildWhenUpstreamBuilding>false</blockBuildWhenUpstreamBuilding>
  <triggers/>
  <concurrentBuild>false</concurrentBuild>
  <builders/>
  <publishers/>
  <buildWrappers/>
</project>
EOF
    else
        echo "Job $job already exists"
    fi
done

# Record initial job count for verification
INITIAL_COUNT=$(count_jobs)
echo "$INITIAL_COUNT" > /tmp/initial_job_count
echo "Initial job count: $INITIAL_COUNT"

# Ensure Firefox is running and focused on Jenkins
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    # Start at the user config page or dashboard to save time? 
    # Task description implies starting from logged in state, usually dashboard.
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
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="