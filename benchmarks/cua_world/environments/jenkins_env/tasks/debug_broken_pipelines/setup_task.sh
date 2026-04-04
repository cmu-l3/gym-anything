#!/bin/bash
# Setup script for Debug Broken Pipelines task
# Creates 3 pipeline jobs each with a distinct bug, then triggers builds so they fail.

echo "=== Setting up Debug Broken Pipelines Task ==="

source /workspace/scripts/task_utils.sh

# Wait for Jenkins API to be ready
echo "Waiting for Jenkins API..."
if ! wait_for_jenkins_api 90; then
    echo "WARNING: Jenkins API may not be ready"
fi

# Get CSRF crumb + cookie jar
echo "Getting CSRF crumb..."
CRUMB_JSON=$(curl -s -u "$JENKINS_USER:$JENKINS_PASS" \
    -c /tmp/jenkins_cookies_dbp \
    "$JENKINS_URL/crumbIssuer/api/json" 2>/dev/null || echo '{}')
CRUMB_FIELD=$(echo "$CRUMB_JSON" | jq -r '.crumbRequestField // empty' 2>/dev/null)
CRUMB_VALUE=$(echo "$CRUMB_JSON" | jq -r '.crumb // empty' 2>/dev/null)
echo "CSRF field: $CRUMB_FIELD"

# Helper arrays for curl auth
AUTH_OPTS=(-u "$JENKINS_USER:$JENKINS_PASS" -b /tmp/jenkins_cookies_dbp)
if [ -n "$CRUMB_FIELD" ] && [ -n "$CRUMB_VALUE" ]; then
    AUTH_OPTS+=(-H "$CRUMB_FIELD: $CRUMB_VALUE")
fi

# ─────────────────────────────────────────────────────────────
# Create credential 'github-access-token' (the CORRECT one)
# Job 2 will reference the WRONG ID; agent must fix it to this one.
# ─────────────────────────────────────────────────────────────
echo "Creating credential 'github-access-token'..."
cat > /tmp/cred_github.xml << 'CREDXML'
<com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>github-access-token</id>
  <description>GitHub access token for CI pipelines</description>
  <username>ci-bot</username>
  <password>ghp_RealTokenValue12345</password>
</com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
CREDXML

curl -s -o /dev/null -w "Credential create HTTP: %{http_code}\n" \
    "${AUTH_OPTS[@]}" \
    -X POST "$JENKINS_URL/credentials/store/system/domain/_/createCredentials" \
    -H "Content-Type: application/xml" \
    --data-binary @/tmp/cred_github.xml 2>/dev/null

# ─────────────────────────────────────────────────────────────
# JOB 1: payment-service-ci
# BUG: Uses 'bat' step (Windows-only) on a Linux agent.
# Fix: Replace 'bat' with 'sh'.
# ─────────────────────────────────────────────────────────────
echo "Creating job 'payment-service-ci' (bat-on-Linux bug)..."
cat > /tmp/job_payment.xml << 'XMLEOF'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>Payment service CI pipeline — builds and tests the payment microservice</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
    <script>pipeline {
    agent any
    stages {
        stage('Build') {
            steps {
                bat 'echo Building payment-service artifact'
            }
        }
        stage('Unit Tests') {
            steps {
                bat 'echo Running payment-service unit tests'
            }
        }
        stage('Package') {
            steps {
                bat 'echo Packaging payment-service'
            }
        }
    }
    post {
        success { echo 'payment-service-ci build succeeded' }
        failure { echo 'payment-service-ci build failed' }
    }
}</script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
XMLEOF

HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
    "${AUTH_OPTS[@]}" \
    -X POST "$JENKINS_URL/createItem?name=payment-service-ci" \
    -H "Content-Type: application/xml" \
    --data-binary @/tmp/job_payment.xml 2>/dev/null)
echo "payment-service-ci created: HTTP $HTTP"

# ─────────────────────────────────────────────────────────────
# JOB 2: user-auth-service
# BUG: References credential 'github-deploy-key' which does NOT exist.
#      The actual credential in the store is 'github-access-token'.
# Fix: Create credential 'github-deploy-key' OR update the job to use 'github-access-token'.
# ─────────────────────────────────────────────────────────────
echo "Creating job 'user-auth-service' (wrong credential ID bug)..."
python3 << 'PYEOF'
import html

script = """pipeline {
    agent any
    stages {
        stage('Checkout') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'github-deploy-key',
                        usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')]) {
                    sh 'echo "Authenticating repository access for ${GIT_USER}"'
                    sh 'echo "Checkout complete"'
                }
            }
        }
        stage('Build') {
            steps {
                sh 'echo "Building user-auth-service"'
                sh 'echo "Compilation successful"'
            }
        }
        stage('Test') {
            steps {
                sh 'echo "Running authentication unit tests"'
                sh 'echo "All tests passed"'
            }
        }
    }
}"""

xml = f"""<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>User authentication service CI — checkout, build, and test the auth microservice</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
    <script>{html.escape(script)}</script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>"""

with open('/tmp/job_auth.xml', 'w') as f:
    f.write(xml)
print("Job 2 XML written")
PYEOF

HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
    "${AUTH_OPTS[@]}" \
    -X POST "$JENKINS_URL/createItem?name=user-auth-service" \
    -H "Content-Type: application/xml" \
    --data-binary @/tmp/job_auth.xml 2>/dev/null)
echo "user-auth-service created: HTTP $HTTP"

# ─────────────────────────────────────────────────────────────
# JOB 3: inventory-api-build
# BUG: The Publish stage requires NEXUS_URL env var; no environment block is set.
# Fix: Add an environment block with NEXUS_URL = 'http://nexus.company.internal:8081'
#      (or any non-empty value), OR remove the explicit error check.
# ─────────────────────────────────────────────────────────────
echo "Creating job 'inventory-api-build' (missing env var bug)..."
cat > /tmp/job_inventory.xml << 'XMLEOF'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>Inventory API build pipeline — compiles, tests, and publishes the inventory service</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
    <script>pipeline {
    agent any
    stages {
        stage('Build') {
            steps {
                sh 'echo "Compiling inventory-api source"'
                sh 'echo "Build artifact generated: inventory-api-1.0.jar"'
            }
        }
        stage('Test') {
            steps {
                sh 'echo "Running inventory-api integration tests"'
                sh 'echo "Tests: 42 passed, 0 failed"'
            }
        }
        stage('Publish') {
            steps {
                sh '''
                    if [ -z "${NEXUS_URL}" ]; then
                        echo "ERROR: NEXUS_URL environment variable is not set in this pipeline."
                        echo "Add an environment block to the pipeline and set NEXUS_URL to your Nexus server URL."
                        exit 1
                    fi
                    echo "Publishing inventory-api-1.0.jar to ${NEXUS_URL}/repository/releases/"
                    echo "Artifact published successfully"
                '''
            }
        }
    }
}</script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
XMLEOF

HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
    "${AUTH_OPTS[@]}" \
    -X POST "$JENKINS_URL/createItem?name=inventory-api-build" \
    -H "Content-Type: application/xml" \
    --data-binary @/tmp/job_inventory.xml 2>/dev/null)
echo "inventory-api-build created: HTTP $HTTP"

# ─────────────────────────────────────────────────────────────
# Trigger initial builds so failures appear in build history
# ─────────────────────────────────────────────────────────────
sleep 3
echo "Triggering initial builds (expected to fail)..."
for JOB in payment-service-ci user-auth-service inventory-api-build; do
    if job_exists "$JOB"; then
        TRIGGER_HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
            "${AUTH_OPTS[@]}" \
            -X POST "$JENKINS_URL/job/$JOB/build" 2>/dev/null)
        echo "Triggered $JOB: HTTP $TRIGGER_HTTP"
    else
        echo "WARNING: $JOB not found, cannot trigger build"
    fi
done

# Wait for builds to run and fail
echo "Waiting 30s for builds to complete (they should fail quickly)..."
sleep 30

# ─────────────────────────────────────────────────────────────
# Record initial build numbers (baseline for detecting new builds)
# ─────────────────────────────────────────────────────────────
echo "Recording initial build baselines..."
for JOB in payment-service-ci user-auth-service inventory-api-build; do
    BUILD_NUM=$(jenkins_api "job/$JOB/api/json" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('lastBuild',{}).get('number',0) if d.get('lastBuild') else 0)" 2>/dev/null || echo "0")
    SAFE_JOB=$(echo "$JOB" | tr '-' '_')
    printf '%s' "$BUILD_NUM" > "/tmp/initial_build_${SAFE_JOB}"
    echo "Initial build number for $JOB: $BUILD_NUM"
done

date +%s > /tmp/task_start_timestamp

# ─────────────────────────────────────────────────────────────
# Start Firefox on Jenkins dashboard
# ─────────────────────────────────────────────────────────────
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox "$JENKINS_URL" > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

if ! wait_for_window "firefox\|mozilla\|jenkins" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Debug Broken Pipelines Setup Complete ==="
echo ""
echo "Three broken pipelines are ready for diagnosis:"
echo "  - payment-service-ci    (has a build failure)"
echo "  - user-auth-service     (has a build failure)"
echo "  - inventory-api-build   (has a build failure)"
echo ""
echo "Examine each job's console output, identify the bug, and fix it."
echo ""
