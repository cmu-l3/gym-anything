#!/bin/bash
# Setup script for Configure Build Artifacts task
# Creates a job with build steps but NO artifacts/retention configured

echo "=== Setting up Configure Build Artifacts Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Jenkins API to be ready
echo "Waiting for Jenkins API..."
if ! wait_for_jenkins_api 60; then
    echo "WARNING: Jenkins API not ready"
fi

# Define Job Name
JOB_NAME="Integration-Tests"

# Create initial job config XML (Freestyle job with shell step, no retention, no publishers)
cat > /tmp/initial_config.xml << 'JOBXML'
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Integration tests for the main application. Generates XML and HTML reports.</description>
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
echo "Running integration tests..."
mkdir -p reports
# Simulate test execution
sleep 2

# Generate dummy JUnit XML
cat &gt; reports/test-report.xml &lt;&lt; 'EOF'
&lt;?xml version="1.0" encoding="UTF-8"?&gt;
&lt;testsuite name="com.example.integration" tests="12" failures="0" errors="0" time="34.521"&gt;
  &lt;testcase classname="com.example.integration.UserServiceTest" name="testCreateUser" time="2.103"/&gt;
&lt;/testsuite&gt;
EOF

# Generate dummy HTML report
cat &gt; reports/coverage-report.html &lt;&lt; 'EOF'
&lt;!DOCTYPE html&gt;
&lt;html&gt;&lt;head&gt;&lt;title&gt;Coverage&lt;/title&gt;&lt;/head&gt;
&lt;body&gt;&lt;h1&gt;Coverage: 88%&lt;/h1&gt;&lt;/body&gt;&lt;/html&gt;
EOF

echo "Reports generated in reports/"</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
JOBXML

# Create the job
echo "Creating job '$JOB_NAME'..."

# Get CSRF crumb
CRUMB_JSON=$(curl -s -u "$JENKINS_USER:$JENKINS_PASS" -c /tmp/jenkins_cookies "$JENKINS_URL/crumbIssuer/api/json" 2>/dev/null || echo "{}")
CRUMB_FIELD=$(echo "$CRUMB_JSON" | jq -r '.crumbRequestField // empty' 2>/dev/null)
CRUMB_VALUE=$(echo "$CRUMB_JSON" | jq -r '.crumb // empty' 2>/dev/null)

if [ -n "$CRUMB_FIELD" ] && [ -n "$CRUMB_VALUE" ]; then
    curl -s -o /dev/null \
        -u "$JENKINS_USER:$JENKINS_PASS" \
        -b /tmp/jenkins_cookies \
        -X POST "$JENKINS_URL/createItem?name=$JOB_NAME" \
        -H "Content-Type: text/xml" \
        -H "$CRUMB_FIELD: $CRUMB_VALUE" \
        --data-binary @/tmp/initial_config.xml
else
    curl -s -o /dev/null \
        -u "$JENKINS_USER:$JENKINS_PASS" \
        -X POST "$JENKINS_URL/createItem?name=$JOB_NAME" \
        -H "Content-Type: text/xml" \
        --data-binary @/tmp/initial_config.xml
fi

# Save initial state for comparison
cp /tmp/initial_config.xml /tmp/original_job_config.xml
date +%s > /tmp/task_start_time.txt

# Ensure Firefox is running and focused on Jenkins
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    DISPLAY=:1 firefox "$JENKINS_URL/job/$JOB_NAME" > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

# Wait for window
wait_for_window "firefox\|mozilla\|jenkins" 30

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="