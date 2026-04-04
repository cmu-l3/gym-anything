#!/bin/bash
set -e
echo "=== Setting up Script Console Audit task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Jenkins API
wait_for_jenkins_api 60

# Record initial state: current plugin count and job count
PLUGIN_COUNT=$(jenkins_api "pluginManager/api/json?depth=1" | jq '.plugins | length' 2>/dev/null || echo "0")
echo "$PLUGIN_COUNT" > /tmp/initial_plugin_count.txt

# Create pre-existing jobs to make audit meaningful
echo "Creating pre-existing jobs..."

# Job 1: webapp-frontend-build (freestyle)
cat <<'JOBXML' | jenkins_cli create-job webapp-frontend-build
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Frontend build for webapp - runs npm install and build</description>
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
      <command>echo "Installing frontend dependencies..."
echo "node --version"
echo "npm install"
echo "npm run build"
echo "Build artifacts generated."</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
JOBXML

# Job 2: api-integration-tests (freestyle)
cat <<'JOBXML' | jenkins_cli create-job api-integration-tests
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Integration test suite for REST API endpoints</description>
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
      <command>echo "Running API integration tests..."
echo "pytest tests/integration/ -v --tb=short"
echo "All 47 tests passed."</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
JOBXML

# Job 3: release-deploy-pipeline (pipeline)
cat <<'JOBXML' | jenkins_cli create-job release-deploy-pipeline
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>Release deployment pipeline for staging and production</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
    <script>pipeline {
    agent any
    stages {
        stage('Build') {
            steps {
                echo 'Building release artifact...'
            }
        }
        stage('Deploy to Staging') {
            steps {
                echo 'Deploying to staging environment...'
            }
        }
        stage('Deploy to Production') {
            steps {
                echo 'Deploying to production environment...'
            }
        }
    }
}</script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
JOBXML

echo "Pre-existing jobs created."

# Verify jobs exist
echo "Verifying jobs..."
for JOB in webapp-frontend-build api-integration-tests release-deploy-pipeline; do
    if job_exists "$JOB"; then
        echo "  ✓ $JOB exists"
    else
        echo "  ✗ $JOB NOT FOUND"
    fi
done

# Record ground truth: full plugin list via API
echo "Recording ground truth plugin list..."
jenkins_api "pluginManager/api/json?depth=1" > /tmp/ground_truth_plugins.json 2>/dev/null
jenkins_api "api/json" > /tmp/ground_truth_jobs.json 2>/dev/null
jenkins_api "api/json" | jq -r '.jobs[].name' > /tmp/ground_truth_job_names.txt 2>/dev/null

# Get Jenkins version for ground truth
JENKINS_VERSION=$(jenkins_api "api/json" | jq -r '.version // empty' 2>/dev/null || \
    curl -sI -u admin:Admin123! http://localhost:8080 | grep -i "X-Jenkins:" | awk '{print $2}' | tr -d '\r')
echo "$JENKINS_VERSION" > /tmp/ground_truth_jenkins_version.txt
echo "Jenkins version: $JENKINS_VERSION"

# Make sure any previous audit file does NOT exist (clean state)
# Note: audit_report.txt is created inside the Jenkins container volume
if [ -f /var/lib/docker/volumes/jenkins_home/_data/audit_report.txt ]; then
    rm -f /var/lib/docker/volumes/jenkins_home/_data/audit_report.txt 2>/dev/null || true
fi

# Ensure Firefox is showing Jenkins dashboard
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    DISPLAY=:1 firefox "$JENKINS_URL" > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

# Wait for Firefox window
wait_for_window "firefox\|mozilla\|jenkins" 30

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="