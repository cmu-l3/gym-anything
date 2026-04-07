#!/bin/bash
# Setup script for Migrate Freestyle to Pipeline task.
# Creates 4 interconnected Freestyle jobs, 2 credentials, and adds 'security-node' label
# to the built-in node so all jobs can execute.
#
# credentials-binding is already a dependency of workflow-aggregator (pre-installed).
# Environment variables are set directly in the shell build step (no EnvInject needed).
# JUnit plugin must be installed if missing — done FIRST with safe restart before job creation.

echo "=== Setting up Migrate Freestyle to Pipeline Task ==="

source /workspace/scripts/task_utils.sh

# Wait for Jenkins API to be ready
echo "Waiting for Jenkins API..."
if ! wait_for_jenkins_api 90; then
    echo "WARNING: Jenkins API may not be ready"
fi

# ── Helper: get CSRF crumb ────────────────────────────────────
get_csrf_crumb() {
    CRUMB_JSON=$(curl -s -u "$JENKINS_USER:$JENKINS_PASS" \
        -c /tmp/jenkins_cookies_mftp \
        "$JENKINS_URL/crumbIssuer/api/json" 2>/dev/null || echo '{}')
    CRUMB_FIELD=$(echo "$CRUMB_JSON" | jq -r '.crumbRequestField // empty' 2>/dev/null)
    CRUMB_VALUE=$(echo "$CRUMB_JSON" | jq -r '.crumb // empty' 2>/dev/null)
    AUTH_OPTS=(-u "$JENKINS_USER:$JENKINS_PASS" -b /tmp/jenkins_cookies_mftp)
    if [ -n "$CRUMB_FIELD" ] && [ -n "$CRUMB_VALUE" ]; then
        AUTH_OPTS+=(-H "$CRUMB_FIELD: $CRUMB_VALUE")
    fi
}

echo "Getting CSRF crumb..."
get_csrf_crumb
echo "CSRF field: $CRUMB_FIELD"

# ── Delete stale outputs BEFORE recording timestamp ───────────
rm -f /tmp/migrate_freestyle_to_pipeline_result.json 2>/dev/null || \
    sudo rm -f /tmp/migrate_freestyle_to_pipeline_result.json 2>/dev/null || true
rm -f /tmp/task_start_timestamp 2>/dev/null || true

# ── Clean up pre-existing target pipeline job ─────────────────
if job_exists "orders-api-pipeline"; then
    echo "Removing pre-existing orders-api-pipeline job..."
    curl -s -o /dev/null -w "  HTTP %{http_code}\n" \
        "${AUTH_OPTS[@]}" \
        -X POST "$JENKINS_URL/job/orders-api-pipeline/doDelete" 2>/dev/null
    sleep 1
fi

# ── Clean up pre-existing source jobs (for idempotency) ───────
for JOB in orders-api-build orders-api-test orders-api-security-scan orders-api-staging-deploy; do
    if job_exists "$JOB"; then
        echo "Removing pre-existing job: $JOB"
        curl -s -o /dev/null -w "  HTTP %{http_code}\n" \
            "${AUTH_OPTS[@]}" \
            -X POST "$JENKINS_URL/job/$JOB/doDelete" 2>/dev/null
        sleep 1
    fi
done

# ── Clean up pre-existing credentials ─────────────────────────
for CRED_ID in staging-db-creds staging-ssh-key; do
    echo "Removing credential '$CRED_ID' if exists..."
    curl -s -o /dev/null \
        "${AUTH_OPTS[@]}" \
        -X POST "$JENKINS_URL/credentials/store/system/domain/_/credential/$CRED_ID/doDelete" \
        2>/dev/null || true
done
sleep 1

# ─────────────────────────────────────────────────────────────
# Create credentials
# ─────────────────────────────────────────────────────────────

echo "Creating credential 'staging-db-creds' (username/password)..."
cat > /tmp/cred_staging_db.xml << 'CREDXML'
<com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>staging-db-creds</id>
  <description>Staging database credentials for integration tests</description>
  <username>dbadmin</username>
  <password>Str0ngP@ss!</password>
</com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
CREDXML

curl -s -o /dev/null -w "Credential staging-db-creds: HTTP %{http_code}\n" \
    "${AUTH_OPTS[@]}" \
    -X POST "$JENKINS_URL/credentials/store/system/domain/_/createCredentials" \
    -H "Content-Type: application/xml" \
    --data-binary @/tmp/cred_staging_db.xml 2>/dev/null

echo "Creating credential 'staging-ssh-key' (secret text)..."
cat > /tmp/cred_staging_ssh.xml << 'CREDXML'
<org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl plugin="plain-credentials">
  <scope>GLOBAL</scope>
  <id>staging-ssh-key</id>
  <description>SSH key for staging deployment server</description>
  <secret>ssh-rsa-AAAA-staging-key-placeholder</secret>
</org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl>
CREDXML

curl -s -o /dev/null -w "Credential staging-ssh-key: HTTP %{http_code}\n" \
    "${AUTH_OPTS[@]}" \
    -X POST "$JENKINS_URL/credentials/store/system/domain/_/createCredentials" \
    -H "Content-Type: application/xml" \
    --data-binary @/tmp/cred_staging_ssh.xml 2>/dev/null

# ─────────────────────────────────────────────────────────────
# Add 'security-node' label to built-in node via Script Console
# (so the Security Scan stage can actually execute)
# ─────────────────────────────────────────────────────────────

echo "Adding 'security-node' label to built-in node..."
GROOVY_SCRIPT='
def node = Jenkins.instance
def currentLabels = node.labelString ?: ""
if (!currentLabels.contains("security-node")) {
    node.setLabelString((currentLabels + " security-node").trim())
    node.save()
    println "Label added: security-node"
} else {
    println "Label already present"
}
'
curl -s -o /dev/null -w "Add label: HTTP %{http_code}\n" \
    "${AUTH_OPTS[@]}" \
    -X POST "$JENKINS_URL/scriptText" \
    --data-urlencode "script=$GROOVY_SCRIPT" 2>/dev/null

# ─────────────────────────────────────────────────────────────
# Ensure required plugins are installed.
# The post_start cache may not include all plugins.
# Install everything needed BEFORE creating jobs.
# ─────────────────────────────────────────────────────────────

REQUIRED_PLUGINS="workflow-aggregator git credentials-binding junit"

echo "Checking required plugins..."
MISSING_PLUGINS=$(jenkins_api "pluginManager/api/json?depth=1" 2>/dev/null | \
    python3 -c "
import sys, json
required = '$REQUIRED_PLUGINS'.split()
try:
    d = json.load(sys.stdin)
    installed = [p['shortName'] for p in d.get('plugins', [])]
    missing = [p for p in required if p not in installed]
    print(' '.join(missing))
except:
    print(' '.join(required))
" 2>/dev/null)

if [ -n "$MISSING_PLUGINS" ]; then
    echo "Missing plugins: $MISSING_PLUGINS"

    # Set Jenkins URL (required for CLI to work)
    echo "Setting Jenkins URL for CLI..."
    CRUMB_FOR_SCRIPT=$(curl -s -u "$JENKINS_USER:$JENKINS_PASS" \
        -c /tmp/jenkins_cookies_script \
        "$JENKINS_URL/crumbIssuer/api/json" 2>/dev/null | \
        jq -r '.crumb // empty' 2>/dev/null)
    curl -s -o /dev/null \
        -u "$JENKINS_USER:$JENKINS_PASS" \
        -b /tmp/jenkins_cookies_script \
        -H "Jenkins-Crumb: $CRUMB_FOR_SCRIPT" \
        --data-urlencode "script=
def jlc = JenkinsLocationConfiguration.get()
jlc.setUrl('http://localhost:8080/')
jlc.save()
println 'Jenkins URL set'
" "$JENKINS_URL/scriptText" 2>/dev/null

    # Download Jenkins CLI jar
    echo "Downloading Jenkins CLI..."
    curl -s "$JENKINS_URL/jnlpJars/jenkins-cli.jar" -o /tmp/jenkins-cli-mftp.jar

    # Install plugins via CLI (reliable method — downloads + restarts)
    echo "Installing plugins via Jenkins CLI..."
    java -jar /tmp/jenkins-cli-mftp.jar \
        -s "$JENKINS_URL" \
        -auth "$JENKINS_USER:$JENKINS_PASS" \
        install-plugin $MISSING_PLUGINS -restart 2>&1 || true

    # Wait for Jenkins to come back after restart
    echo "Waiting for Jenkins to restart after plugin installation..."
    sleep 20
    if ! wait_for_jenkins_api 180; then
        echo "WARNING: Jenkins may not have restarted properly"
    fi
    echo "Jenkins is back up after plugin installation"

    # Re-acquire CSRF crumb after restart
    get_csrf_crumb
    echo "CSRF crumb refreshed: $CRUMB_FIELD"

    # Verify critical plugins are now present
    echo "Verifying plugins..."
    jenkins_api "pluginManager/api/json?depth=1" 2>/dev/null | \
        python3 -c "
import sys, json
critical = ['workflow-aggregator', 'workflow-job', 'git', 'credentials-binding', 'junit']
try:
    d = json.load(sys.stdin)
    installed = [p['shortName'] for p in d.get('plugins', [])]
    for p in critical:
        status = 'OK' if p in installed else 'MISSING'
        print(f'  {p}: {status}')
except Exception as e:
    print(f'  Error checking plugins: {e}')
" 2>/dev/null
else
    echo "All required plugins already installed"
fi

sleep 2

# ── Helper: create job with retry ─────────────────────────────
create_job_with_retry() {
    local job_name="$1"
    local xml_file="$2"
    local max_retries=3
    local attempt=0

    while [ $attempt -lt $max_retries ]; do
        attempt=$((attempt + 1))
        HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
            "${AUTH_OPTS[@]}" \
            -X POST "$JENKINS_URL/createItem?name=$job_name" \
            -H "Content-Type: application/xml" \
            --data-binary "@$xml_file" 2>/dev/null)
        echo "  $job_name attempt $attempt: HTTP $HTTP"

        if [ "$HTTP" = "200" ]; then
            return 0
        fi

        # If 503 (Service Unavailable), Jenkins may be restarting — wait and retry
        if [ "$HTTP" = "503" ] || [ "$HTTP" = "000" ]; then
            echo "  Jenkins unavailable, waiting 15s before retry..."
            sleep 15
            wait_for_jenkins_api 60
            get_csrf_crumb
        else
            # For other errors, wait briefly and retry
            sleep 3
        fi
    done
    echo "  FAILED to create $job_name after $max_retries attempts"
    return 1
}

# ─────────────────────────────────────────────────────────────
# JOB 1: orders-api-build
# Freestyle with SCM, 3 parameters, shell build step,
# artifact archiving, downstream trigger, cron trigger, log rotation
# ─────────────────────────────────────────────────────────────

echo "Creating job 'orders-api-build'..."
python3 << 'PYEOF'
import html

shell_cmd = r"""echo "=== Building Orders API ==="
echo "Branch: ${BRANCH_NAME}, Profile: ${BUILD_PROFILE}"
mkdir -p target
echo "orders-api-1.4.2-${BUILD_PROFILE}.jar" > target/orders-api.jar
echo "Build artifact generated"
if [ "${SKIP_TESTS}" = "false" ]; then
  echo "Running unit tests..."
  echo "All 47 unit tests passed"
fi"""

xml = f"""<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Build job for Orders API service - compiles, runs unit tests, and packages artifact</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.StringParameterDefinition>
          <name>BRANCH_NAME</name>
          <description>Git branch to build</description>
          <defaultValue>main</defaultValue>
          <trim>false</trim>
        </hudson.model.StringParameterDefinition>
        <hudson.model.BooleanParameterDefinition>
          <name>SKIP_TESTS</name>
          <description>Skip unit tests</description>
          <defaultValue>false</defaultValue>
        </hudson.model.BooleanParameterDefinition>
        <hudson.model.ChoiceParameterDefinition>
          <name>BUILD_PROFILE</name>
          <description>Maven build profile</description>
          <choices class="java.util.Arrays$ArrayList">
            <a class="string-array">
              <string>dev</string>
              <string>staging</string>
              <string>production</string>
            </a>
          </choices>
        </hudson.model.ChoiceParameterDefinition>
      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
    <jenkins.model.BuildDiscarderProperty>
      <strategy class="hudson.tasks.LogRotator">
        <daysToKeep>-1</daysToKeep>
        <numToKeep>10</numToKeep>
        <artifactDaysToKeep>-1</artifactDaysToKeep>
        <artifactNumToKeep>5</artifactNumToKeep>
      </strategy>
    </jenkins.model.BuildDiscarderProperty>
  </properties>
  <scm class="hudson.plugins.git.GitSCM" plugin="git">
    <configVersion>2</configVersion>
    <userRemoteConfigs>
      <hudson.plugins.git.UserRemoteConfig>
        <url>https://github.com/jenkinsci/pipeline-examples.git</url>
      </hudson.plugins.git.UserRemoteConfig>
    </userRemoteConfigs>
    <branches>
      <hudson.plugins.git.BranchSpec>
        <name>*/master</name>
      </hudson.plugins.git.BranchSpec>
    </branches>
    <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
    <submoduleCfg class="empty-list"/>
    <extensions/>
  </scm>
  <canRoam>true</canRoam>
  <disabled>false</disabled>
  <blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>
  <blockBuildWhenUpstreamBuilding>false</blockBuildWhenUpstreamBuilding>
  <triggers>
    <hudson.triggers.TimerTrigger>
      <spec>H/30 * * * *</spec>
    </hudson.triggers.TimerTrigger>
  </triggers>
  <concurrentBuild>false</concurrentBuild>
  <builders>
    <hudson.tasks.Shell>
      <command>{html.escape(shell_cmd)}</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers>
    <hudson.tasks.ArtifactArchiver>
      <artifacts>target/*.jar</artifacts>
      <allowEmptyArchive>true</allowEmptyArchive>
      <onlyIfSuccessful>false</onlyIfSuccessful>
      <fingerprint>false</fingerprint>
      <defaultExcludes>true</defaultExcludes>
      <caseSensitive>true</caseSensitive>
    </hudson.tasks.ArtifactArchiver>
    <hudson.tasks.BuildTrigger>
      <childProjects>orders-api-test</childProjects>
      <threshold>
        <name>SUCCESS</name>
        <ordinal>0</ordinal>
        <color>BLUE</color>
        <completeBuild>true</completeBuild>
      </threshold>
    </hudson.tasks.BuildTrigger>
  </publishers>
  <buildWrappers/>
</project>"""

with open('/tmp/job_orders_build.xml', 'w') as f:
    f.write(xml)
print("Job 1 XML written")
PYEOF

create_job_with_retry "orders-api-build" "/tmp/job_orders_build.xml"

# ─────────────────────────────────────────────────────────────
# JOB 2: orders-api-test
# Freestyle with credential binding, env vars in shell command,
# JUnit publishing, downstream trigger
# ─────────────────────────────────────────────────────────────

echo "Creating job 'orders-api-test'..."
python3 << 'PYEOF'
import html

# Environment variables DB_HOST and DB_PORT are set at the top of the shell command.
# This is a common freestyle pattern. The agent must extract these and put them in
# the pipeline's environment {} block.
shell_cmd = r"""# Environment configuration
export DB_HOST=orders-db.staging.internal
export DB_PORT=5432

echo "=== Running Integration Tests ==="
echo "Suite: ${TEST_SUITE}"
echo "Connecting to ${DB_HOST}:${DB_PORT}"
mkdir -p test-reports
cat > test-reports/results.xml << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="OrdersIntegrationTests" tests="12" failures="0" errors="0" time="34.5">
  <testcase classname="com.company.orders.CartTest" name="testAddItem" time="1.2"/>
  <testcase classname="com.company.orders.CartTest" name="testRemoveItem" time="0.8"/>
  <testcase classname="com.company.orders.PaymentTest" name="testProcessPayment" time="3.1"/>
  <testcase classname="com.company.orders.PaymentTest" name="testRefund" time="2.7"/>
</testsuite>
XMLEOF
echo "Integration tests completed"
"""

xml = f"""<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Integration test job for Orders API - runs test suite against staging database</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.StringParameterDefinition>
          <name>TEST_SUITE</name>
          <description>Test suite to execute</description>
          <defaultValue>full</defaultValue>
          <trim>false</trim>
        </hudson.model.StringParameterDefinition>
      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
  </properties>
  <scm class="hudson.scm.NullSCM"/>
  <canRoam>true</canRoam>
  <disabled>false</disabled>
  <blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>
  <blockBuildWhenUpstreamBuilding>false</blockBuildWhenUpstreamBuilding>
  <triggers/>
  <concurrentBuild>false</concurrentBuild>
  <builders>
    <hudson.tasks.Shell>
      <command>{html.escape(shell_cmd)}</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers>
    <hudson.tasks.junit.JUnitResultArchiver plugin="junit">
      <testResults>**/test-reports/*.xml</testResults>
      <keepLongStdio>false</keepLongStdio>
      <healthScaleFactor>1.0</healthScaleFactor>
      <allowEmptyResults>true</allowEmptyResults>
    </hudson.tasks.junit.JUnitResultArchiver>
    <hudson.tasks.BuildTrigger>
      <childProjects>orders-api-security-scan</childProjects>
      <threshold>
        <name>SUCCESS</name>
        <ordinal>0</ordinal>
        <color>BLUE</color>
        <completeBuild>true</completeBuild>
      </threshold>
    </hudson.tasks.BuildTrigger>
  </publishers>
  <buildWrappers>
    <org.jenkinsci.plugins.credentialsbinding.impl.SecretBuildWrapper plugin="credentials-binding">
      <bindings>
        <org.jenkinsci.plugins.credentialsbinding.impl.UsernamePasswordMultiBinding>
          <credentialsId>staging-db-creds</credentialsId>
          <usernameVariable>DB_USER</usernameVariable>
          <passwordVariable>DB_PASS</passwordVariable>
        </org.jenkinsci.plugins.credentialsbinding.impl.UsernamePasswordMultiBinding>
      </bindings>
    </org.jenkinsci.plugins.credentialsbinding.impl.SecretBuildWrapper>
  </buildWrappers>
</project>"""

with open('/tmp/job_orders_test.xml', 'w') as f:
    f.write(xml)
print("Job 2 XML written")
PYEOF

create_job_with_retry "orders-api-test" "/tmp/job_orders_test.xml"

# ─────────────────────────────────────────────────────────────
# JOB 3: orders-api-security-scan
# Freestyle with node restriction, artifact archiving,
# downstream trigger
# ─────────────────────────────────────────────────────────────

echo "Creating job 'orders-api-security-scan'..."
cat > /tmp/job_orders_security.xml << 'XMLEOF'
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Security scan job for Orders API - runs OWASP dependency check and generates report</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <scm class="hudson.scm.NullSCM"/>
  <assignedNode>security-node</assignedNode>
  <canRoam>false</canRoam>
  <disabled>false</disabled>
  <blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>
  <blockBuildWhenUpstreamBuilding>false</blockBuildWhenUpstreamBuilding>
  <triggers/>
  <concurrentBuild>false</concurrentBuild>
  <builders>
    <hudson.tasks.Shell>
      <command>echo "=== Running OWASP Dependency Check ==="
mkdir -p security-reports
echo "&lt;report&gt;&lt;summary&gt;No critical vulnerabilities&lt;/summary&gt;&lt;/report&gt;" > security-reports/owasp-report.xml
echo "Security scan complete"</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers>
    <hudson.tasks.ArtifactArchiver>
      <artifacts>security-reports/**</artifacts>
      <allowEmptyArchive>true</allowEmptyArchive>
      <onlyIfSuccessful>false</onlyIfSuccessful>
      <fingerprint>false</fingerprint>
      <defaultExcludes>true</defaultExcludes>
      <caseSensitive>true</caseSensitive>
    </hudson.tasks.ArtifactArchiver>
    <hudson.tasks.BuildTrigger>
      <childProjects>orders-api-staging-deploy</childProjects>
      <threshold>
        <name>SUCCESS</name>
        <ordinal>0</ordinal>
        <color>BLUE</color>
        <completeBuild>true</completeBuild>
      </threshold>
    </hudson.tasks.BuildTrigger>
  </publishers>
  <buildWrappers/>
</project>
XMLEOF

create_job_with_retry "orders-api-security-scan" "/tmp/job_orders_security.xml"

# ─────────────────────────────────────────────────────────────
# JOB 4: orders-api-staging-deploy
# Freestyle with choice/boolean params, secret text
# credential binding, shell build step
# ─────────────────────────────────────────────────────────────

echo "Creating job 'orders-api-staging-deploy'..."
cat > /tmp/job_orders_deploy.xml << 'XMLEOF'
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Staging deployment job for Orders API - deploys build artifact to selected AWS region</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.ChoiceParameterDefinition>
          <name>DEPLOY_REGION</name>
          <description>AWS deployment region</description>
          <choices class="java.util.Arrays$ArrayList">
            <a class="string-array">
              <string>us-east-1</string>
              <string>eu-west-1</string>
              <string>ap-southeast-1</string>
            </a>
          </choices>
        </hudson.model.ChoiceParameterDefinition>
        <hudson.model.BooleanParameterDefinition>
          <name>FORCE_DEPLOY</name>
          <description>Force deployment even if health checks fail</description>
          <defaultValue>false</defaultValue>
        </hudson.model.BooleanParameterDefinition>
      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
  </properties>
  <scm class="hudson.scm.NullSCM"/>
  <canRoam>true</canRoam>
  <disabled>false</disabled>
  <blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>
  <blockBuildWhenUpstreamBuilding>false</blockBuildWhenUpstreamBuilding>
  <triggers/>
  <concurrentBuild>false</concurrentBuild>
  <builders>
    <hudson.tasks.Shell>
      <command>echo "=== Deploying to Staging ==="
echo "Region: ${DEPLOY_REGION}, Force: ${FORCE_DEPLOY}"
echo "Using deployment credentials"
echo "Deployment to ${DEPLOY_REGION} completed successfully"</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers>
    <org.jenkinsci.plugins.credentialsbinding.impl.SecretBuildWrapper plugin="credentials-binding">
      <bindings>
        <org.jenkinsci.plugins.credentialsbinding.impl.StringBinding>
          <credentialsId>staging-ssh-key</credentialsId>
          <variable>STAGING_KEY</variable>
        </org.jenkinsci.plugins.credentialsbinding.impl.StringBinding>
      </bindings>
    </org.jenkinsci.plugins.credentialsbinding.impl.SecretBuildWrapper>
  </buildWrappers>
</project>
XMLEOF

create_job_with_retry "orders-api-staging-deploy" "/tmp/job_orders_deploy.xml"

sleep 3

# ─────────────────────────────────────────────────────────────
# Verify all four source jobs exist
# ─────────────────────────────────────────────────────────────

echo "Verifying jobs were created..."
ALL_OK=true
for JOB in orders-api-build orders-api-test orders-api-security-scan orders-api-staging-deploy; do
    if job_exists "$JOB"; then
        echo "  OK: $JOB exists"
    else
        echo "  FAIL: $JOB MISSING"
        ALL_OK=false
    fi
done

if [ "$ALL_OK" = "false" ]; then
    echo "ERROR: Not all jobs were created. Check logs above."
fi

# ─────────────────────────────────────────────────────────────
# Trigger one chain run so build history shows the relationships
# ─────────────────────────────────────────────────────────────

echo "Triggering initial chain run..."
curl -s -o /dev/null -w "Trigger build: HTTP %{http_code}\n" \
    "${AUTH_OPTS[@]}" \
    -X POST "$JENKINS_URL/job/orders-api-build/buildWithParameters?BRANCH_NAME=main&SKIP_TESTS=false&BUILD_PROFILE=dev" \
    2>/dev/null

echo "Waiting for full chain to complete (up to 90s)..."
CHAIN_TIMEOUT=90
CHAIN_ELAPSED=0
while [ $CHAIN_ELAPSED -lt $CHAIN_TIMEOUT ]; do
    DEPLOY_RESULT=$(jenkins_api "job/orders-api-staging-deploy/lastBuild/api/json" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',''))" 2>/dev/null || echo "")
    if [ -n "$DEPLOY_RESULT" ]; then
        echo "Chain completed: deploy result=$DEPLOY_RESULT (after ${CHAIN_ELAPSED}s)"
        break
    fi
    sleep 5
    CHAIN_ELAPSED=$((CHAIN_ELAPSED + 5))
done

# Log all build results
for JOB in orders-api-build orders-api-test orders-api-security-scan orders-api-staging-deploy; do
    RESULT=$(jenkins_api "job/$JOB/lastBuild/api/json" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result','UNKNOWN'))" 2>/dev/null || echo "NO_BUILD")
    echo "  $JOB last build: $RESULT"
done

# ─────────────────────────────────────────────────────────────
# Record task start timestamp (AFTER setup, before agent starts)
# ─────────────────────────────────────────────────────────────

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

# Refresh to show all jobs
DISPLAY=:1 xdotool key F5 2>/dev/null || true
sleep 3

take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Migrate Freestyle to Pipeline Setup Complete ==="
echo ""
echo "Four source Freestyle jobs are ready:"
echo "  - orders-api-build           (SCM, 3 params, artifacts, cron trigger, log rotation)"
echo "  - orders-api-test            (1 param, credential binding, env vars, JUnit)"
echo "  - orders-api-security-scan   (node restriction, artifacts)"
echo "  - orders-api-staging-deploy  (2 params, credential binding)"
echo ""
echo "Two credentials provisioned: staging-db-creds, staging-ssh-key"
echo "Built-in node labeled: security-node"
echo ""
echo "The agent must create 'orders-api-pipeline' consolidating all four."
echo ""
