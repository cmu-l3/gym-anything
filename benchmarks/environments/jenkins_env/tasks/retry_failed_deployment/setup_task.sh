#!/bin/bash
# Setup script for Retry Failed Deployment task
# Creates a parameterized job and generates a specific build history

echo "=== Setting up Retry Failed Deployment Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Jenkins API
if ! wait_for_jenkins_api 60; then
    echo "WARNING: Jenkins API not ready"
fi

JOB_NAME="Payment-Gateway-Deploy"

# 1. Create the parameterized job config
cat > /tmp/deploy_job_config.xml << 'JOBXML'
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Deploys the Payment Gateway service to cloud regions.</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.StringParameterDefinition>
          <name>ARTIFACT_TAG</name>
          <description>The version tag to deploy (e.g., v1.0.2-rc1)</description>
          <defaultValue>latest</defaultValue>
          <trim>true</trim>
        </hudson.model.StringParameterDefinition>
        <hudson.model.ChoiceParameterDefinition>
          <name>REGION</name>
          <description>Target AWS Region</description>
          <choices class="java.util.Arrays$ArrayList">
            <a class="string-array">
              <string>us-east-1</string>
              <string>us-west-2</string>
              <string>eu-central-1</string>
              <string>ap-northeast-1</string>
            </a>
          </choices>
        </hudson.model.ChoiceParameterDefinition>
        <hudson.model.BooleanParameterDefinition>
          <name>FORCE_RESTART</name>
          <description>Force a full container restart (clears local cache)</description>
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
      <command>echo "Deploying $ARTIFACT_TAG to $REGION..."
echo "Force Restart: $FORCE_RESTART"
sleep 2
if [ "$FORCE_RESTART" = "true" ]; then
  echo "Cache cleared. Deployment successful."
else
  # Simulate failure for the specific bad tag if restart is false
  if [[ "$ARTIFACT_TAG" == *"rc8"* ]]; then
    echo "ERROR: Deployment failed due to stale cache lock."
    exit 1
  fi
fi
echo "Deployment complete."</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
JOBXML

# 2. Create the job via CLI
echo "Creating job '$JOB_NAME'..."
if [ ! -f /tmp/jenkins-cli.jar ]; then
    curl -s "$JENKINS_URL/jnlpJars/jenkins-cli.jar" -o /tmp/jenkins-cli.jar
fi

java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" create-job "$JOB_NAME" < /tmp/deploy_job_config.xml

# 3. Generate randomized parameters for the history
# We need Build #3 to be the "failed" one the agent must copy
RANDOM_SUFFIX=$(shuf -i 100-999 -n 1)
TAG_BUILD_1="v2.3.0-stable"
TAG_BUILD_2="v2.3.1-hotfix"
# This is the target tag the agent must copy (contains rc8 which triggers fail script)
TARGET_TAG="paygw-2024.10.12-rc8-x${RANDOM_SUFFIX}" 

# Randomize the region for Build #3
REGIONS=("us-east-1" "us-west-2" "eu-central-1" "ap-northeast-1")
TARGET_REGION=${REGIONS[$RANDOM % ${#REGIONS[@]} ]}

echo "Target Configuration (Ground Truth):"
echo "  Tag: $TARGET_TAG"
echo "  Region: $TARGET_REGION"

# Save ground truth for verification (hidden from agent)
cat > /tmp/expected_params.json << EOF
{
  "expected_tag": "$TARGET_TAG",
  "expected_region": "$TARGET_REGION",
  "expected_force_restart": true,
  "failed_build_number": 3
}
EOF
chmod 644 /tmp/expected_params.json

# 4. Generate Build History
echo "Generating build history..."

# Build 1 (Success)
java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" build "$JOB_NAME" -p ARTIFACT_TAG="$TAG_BUILD_1" -p REGION="us-east-1" -p FORCE_RESTART=false -w

# Build 2 (Success)
java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" build "$JOB_NAME" -p ARTIFACT_TAG="$TAG_BUILD_2" -p REGION="us-west-2" -p FORCE_RESTART=false -w

# Build 3 (The FAILURE to be retried)
# Note: The job script is designed to fail if tag contains 'rc8' and restart is false
java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" build "$JOB_NAME" -p ARTIFACT_TAG="$TARGET_TAG" -p REGION="$TARGET_REGION" -p FORCE_RESTART=false -w || true

# 5. Launch Firefox
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox "$JENKINS_URL/job/$JOB_NAME" > /tmp/firefox.log 2>&1 &
    sleep 5
fi

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 6. Capture initial state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="