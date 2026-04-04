#!/bin/bash
# Setup script for Restore Job from Backup task
# Creates a complex pipeline job, backs up its config, then deletes it

echo "=== Setting up Restore Job Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Jenkins API to be ready
echo "Waiting for Jenkins API..."
if ! wait_for_jenkins_api 60; then
    echo "WARNING: Jenkins API not ready"
fi

JOB_NAME="Production-Deploy-Pipeline"
BACKUP_DIR="/home/ga/jenkins_backup"
BACKUP_FILE="$BACKUP_DIR/${JOB_NAME}-config.xml"

# Create backup directory
mkdir -p "$BACKUP_DIR"
chown ga:ga "$BACKUP_DIR"

# Define the complex job configuration XML
# Includes: Pipeline script, Parameters, SCM Trigger, Log Rotation
cat > /tmp/original_config.xml << 'JOBXML'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>Production deployment pipeline for the Java Maven application.&#xd;
  Builds, tests, and deploys to the target environment.</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.StringParameterDefinition>
          <name>DEPLOY_ENV</name>
          <description>Target deployment environment</description>
          <defaultValue>staging</defaultValue>
          <trim>false</trim>
        </hudson.model.StringParameterDefinition>
        <hudson.model.ChoiceParameterDefinition>
          <name>BUILD_TYPE</name>
          <description>Type of build to execute</description>
          <choices class="java.util.Arrays$ArrayList">
            <a class="string-array">
              <string>release</string>
              <string>snapshot</string>
              <string>hotfix</string>
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
        <artifactNumToKeep>-1</artifactNumToKeep>
      </strategy>
    </jenkins.model.BuildDiscarderProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
    <script>pipeline {
    agent any
    parameters {
        string(name: &apos;DEPLOY_ENV&apos;, defaultValue: &apos;staging&apos;, description: &apos;Target deployment environment&apos;)
        choice(name: &apos;BUILD_TYPE&apos;, choices: [&apos;release&apos;, &apos;snapshot&apos;, &apos;hotfix&apos;], description: &apos;Type of build to execute&apos;)
    }
    stages {
        stage(&apos;Checkout&apos;) {
            steps {
                git url: &apos;https://github.com/jenkins-docs/simple-java-maven-app&apos;, branch: &apos;master&apos;
            }
        }
        stage(&apos;Build&apos;) {
            steps {
                echo &quot;Building ${params.BUILD_TYPE} for ${params.DEPLOY_ENV}&quot;
            }
        }
    }
}</script>
    <sandbox>true</sandbox>
  </definition>
  <triggers>
    <hudson.triggers.SCMTrigger>
      <spec>H/15 * * * *</spec>
      <ignorePostCommitHooks>false</ignorePostCommitHooks>
    </hudson.triggers.SCMTrigger>
  </triggers>
  <disabled>false</disabled>
</flow-definition>
JOBXML

echo "Creating initial job to validate configuration..."
# We create it temporarily to ensure Jenkins accepts the XML and to simulate the "deleted" state correctly
# (We could just write the XML to disk, but creating and exporting ensures it's 100% valid Jenkins XML)

# Create job via CLI (simpler than curl for auth sometimes)
if [ ! -f /tmp/jenkins-cli.jar ]; then
    curl -s "$JENKINS_URL/jnlpJars/jenkins-cli.jar" -o /tmp/jenkins-cli.jar
fi

java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" create-job "$JOB_NAME" < /tmp/original_config.xml

# Verify it was created
if ! job_exists "$JOB_NAME"; then
    echo "ERROR: Failed to create initial job. Using raw XML as backup."
    cp /tmp/original_config.xml "$BACKUP_FILE"
else
    echo "Job created. exporting canonical configuration to backup..."
    # Export the config back from Jenkins (canonical format)
    jenkins_api "job/$JOB_NAME/config.xml" > "$BACKUP_FILE"
    
    # Delete the job
    echo "Deleting job to simulate accidental deletion..."
    java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" delete-job "$JOB_NAME"
fi

# Ensure backup exists and has content
if [ ! -s "$BACKUP_FILE" ]; then
    echo "ERROR: Backup file is empty or missing!"
    exit 1
fi

chown ga:ga "$BACKUP_FILE"
chmod 644 "$BACKUP_FILE"

echo "Backup created at: $BACKUP_FILE"
echo "Job '$JOB_NAME' has been deleted from Jenkins."

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Firefox is open
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$JENKINS_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Maximize and focus
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="