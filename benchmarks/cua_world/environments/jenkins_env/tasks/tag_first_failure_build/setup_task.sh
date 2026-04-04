#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: tag_first_failure_build ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Jenkins
wait_for_jenkins_api 120

JOB_NAME="Nightly-Quality-Gate"
REPO_DIR="/home/ga/maven-app-repo"

# cleanup previous run
rm -rf "$REPO_DIR"
jenkins_cli delete-job "$JOB_NAME" 2>/dev/null || true

# 1. Setup local git repo with valid code
echo "Setting up local git repository..."
mkdir -p "$REPO_DIR"
# Copy sample app logic (simulated or real download)
# We'll create a minimal valid maven structure to avoid external dependencies failure if internet is flaky
# But the environment spec says we have internet and valid repos. Let's use the one from the env docs if available or create minimal.
# The previous examples used 'jenkins-docs/simple-java-maven-app'. We will use that.

if [ ! -d "$REPO_DIR/.git" ]; then
    git clone https://github.com/jenkins-docs/simple-java-maven-app.git "$REPO_DIR"
fi

cd "$REPO_DIR"
# Reset to a known state
git checkout master 2>/dev/null || git checkout main
git config user.email "devops@example.com"
git config user.name "DevOps Bot"

# 2. Create the Pipeline Job
echo "Creating Pipeline job '$JOB_NAME'..."
cat <<EOF > /tmp/job_config.xml
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>Daily build for quality assurance. Check console logs for failure details.</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps">
    <scm class="hudson.plugins.git.GitSCM" plugin="git">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>file://$REPO_DIR</url>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/master</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
      <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
      <submoduleCfg class="list"/>
      <extensions/>
    </scm>
    <scriptPath>jenkins/Jenkinsfile</scriptPath>
    <lightweight>true</lightweight>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
EOF

jenkins_cli create-job "$JOB_NAME" < /tmp/job_config.xml

# 3. Generate Build History
echo "Generating build history..."

# Helper to wait for build
wait_for_completion() {
    local jname="$1"
    while [ "$(get_job_status "$jname" | jq -r .inQueue)" == "true" ] || [ "$(get_job_status "$jname" | jq -r .lastBuild.building)" == "true" ]; do
        sleep 1
    done
}

# Build 1: Success
echo "Triggering Build #1 (Success)..."
jenkins_cli build "$JOB_NAME"
wait_for_completion "$JOB_NAME"

# Build 2: Success
echo "Triggering Build #2 (Success)..."
jenkins_cli build "$JOB_NAME"
wait_for_completion "$JOB_NAME"

# BREAK THE BUILD
echo "Injecting regression..."
# We modify the Jenkinsfile to force a specific maven error or modify pom.xml
# Let's modify pom.xml to have a bad parent
sed -i 's/<groupId>org.jenkins-ci.main<\/groupId>/<groupId>org.jenkins-ci.main.BROKEN<\/groupId>/' pom.xml
git add pom.xml
git commit -m "Update parent POM version (broken)"

# Build 3: FAILURE (The Target)
echo "Triggering Build #3 (FAILURE - REGRESSION START)..."
jenkins_cli build "$JOB_NAME" || true
wait_for_completion "$JOB_NAME"

# Identify this build as the target
TARGET_BUILD=$(get_last_build "$JOB_NAME" | jq -r .number)
echo "$TARGET_BUILD" > /tmp/target_build_id.txt
echo "Target Build ID: $TARGET_BUILD"

# Build 4: FAILURE
echo "Triggering Build #4 (FAILURE)..."
jenkins_cli build "$JOB_NAME" || true
wait_for_completion "$JOB_NAME"

# Build 5: FAILURE
echo "Triggering Build #5 (FAILURE)..."
jenkins_cli build "$JOB_NAME" || true
wait_for_completion "$JOB_NAME"

# 4. Setup Agent State
# Launch Firefox pointing to the job page
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/job/$JOB_NAME/' > /dev/null 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
            break
        fi
        sleep 1
    done
fi

# Maximize
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Screenshot initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="