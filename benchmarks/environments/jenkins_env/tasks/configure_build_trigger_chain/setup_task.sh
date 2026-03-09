#!/bin/bash
set -e
echo "=== Setting up configure_build_trigger_chain task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Jenkins API
echo "Waiting for Jenkins API..."
wait_for_jenkins_api 60

# Delete jobs if they already exist (clean state)
for JOB_NAME in inventory-build inventory-test inventory-deploy; do
    if job_exists "$JOB_NAME"; then
        echo "Removing existing job: $JOB_NAME"
        jenkins_cli delete-job "$JOB_NAME" 2>/dev/null || true
    fi
done

sleep 2

# Create inventory-build job
echo "Creating inventory-build job..."
cat <<'BUILDXML' | jenkins_cli create-job inventory-build
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Compiles the inventory-service application (Maven build simulation)</description>
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
      <command>#!/bin/bash
echo "============================================"
echo "  inventory-service :: COMPILE STAGE"
echo "============================================"
echo ""
echo "[INFO] Scanning for projects..."
echo "[INFO] "
echo "[INFO] --- maven-compiler-plugin:3.11.0:compile (default-compile) @ inventory-service ---"
echo "[INFO] Changes detected - recompiling the module!"
sleep 2
echo "[INFO] Compiling 47 source files to /target/classes"
echo "[INFO] Compiling 12 test source files to /target/test-classes"
echo ""
echo "[INFO] BUILD SUCCESS"
echo "[INFO] Total time: 2.134 s"
echo "============================================"</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
BUILDXML

# Create inventory-test job
echo "Creating inventory-test job..."
cat <<'TESTXML' | jenkins_cli create-job inventory-test
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Runs the test suite for inventory-service (JUnit + integration tests)</description>
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
      <command>#!/bin/bash
echo "============================================"
echo "  inventory-service :: TEST STAGE"
echo "============================================"
echo ""
echo "[INFO] --- maven-surefire-plugin:3.1.2:test (default-test) @ inventory-service ---"
echo "[INFO] Using JUnit Platform to run tests"
sleep 2
echo ""
echo "[INFO] Tests run: 23, Failures: 0, Errors: 0, Skipped: 1"
echo "[INFO] "
echo "[INFO] --- maven-failsafe-plugin:3.1.2:integration-test ---"
sleep 1
echo "[INFO] Integration tests run: 8, Failures: 0, Errors: 0"
echo ""
echo "[INFO] BUILD SUCCESS"
echo "[INFO] Total time: 3.892 s"
echo "============================================"</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
TESTXML

# Create inventory-deploy job
echo "Creating inventory-deploy job..."
cat <<'DEPLOYXML' | jenkins_cli create-job inventory-deploy
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Deploys inventory-service to the staging environment</description>
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
      <command>#!/bin/bash
echo "============================================"
echo "  inventory-service :: DEPLOY STAGE"
echo "============================================"
echo ""
echo "[deploy] Connecting to staging server: staging-01.internal.corp"
echo "[deploy] Uploading artifact: inventory-service-2.4.1-SNAPSHOT.jar"
sleep 2
echo "[deploy] Stopping existing service..."
echo "[deploy] Deploying new version..."
sleep 1
echo "[deploy] Starting service on port 8090..."
echo "[deploy] Health check: HTTP 200 OK"
echo ""
echo "[INFO] DEPLOYMENT SUCCESSFUL"
echo "[INFO] Version 2.4.1-SNAPSHOT deployed to staging"
echo "[INFO] Total time: 3.240 s"
echo "============================================"</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
DEPLOYXML

sleep 2

# Save initial configs as baseline (for anti-gaming)
echo "Saving baseline configurations..."
mkdir -p /tmp/baseline_configs
for JOB_NAME in inventory-build inventory-test inventory-deploy; do
    jenkins_api "job/${JOB_NAME}/config.xml" > "/tmp/baseline_configs/${JOB_NAME}.xml" 2>/dev/null
done

# Record initial job count
INITIAL_JOB_COUNT=$(count_jobs)
echo "$INITIAL_JOB_COUNT" > /tmp/initial_job_count.txt

# Verify all three jobs exist
echo "Verifying jobs were created..."
for JOB_NAME in inventory-build inventory-test inventory-deploy; do
    if job_exists "$JOB_NAME"; then
        echo "  ✓ $JOB_NAME exists"
    else
        echo "  ✗ $JOB_NAME MISSING - setup failed!"
        exit 1
    fi
done

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$JENKINS_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Focus the window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Refresh Firefox to show the new jobs
echo "Refreshing Firefox..."
DISPLAY=:1 xdotool key F5 2>/dev/null || true
sleep 3

# Take screenshot of initial state (for evidence)
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo ""
echo "=== Task setup complete ==="
echo "Three jobs created: inventory-build, inventory-test, inventory-deploy"
echo "No triggers configured between them (agent must configure triggers)"
echo ""