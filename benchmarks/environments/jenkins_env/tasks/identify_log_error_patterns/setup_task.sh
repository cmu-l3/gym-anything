#!/bin/bash
set -e
echo "=== Setting up Identify Log Error Patterns Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Jenkins to be ready
if ! wait_for_jenkins_api 60; then
    echo "ERROR: Jenkins API not ready"
    exit 1
fi

JOB_NAME="Payment-Service"
TRUTH_FILE="/root/truth_timeout_builds.txt"
rm -f "$TRUTH_FILE"

# 1. Create the Parameterized Job
# We create a job that accepts a 'SCENARIO' parameter and generates logs accordingly
echo "Creating generator job..."

cat > /tmp/generator_config.xml << 'EOF'
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Payment Service Build Pipeline</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.StringParameterDefinition>
          <name>SCENARIO</name>
          <defaultValue>SUCCESS</defaultValue>
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
      <command>
echo "Starting Payment-Service build..."
echo "Download dependencies..."
sleep 0.5
echo "[INFO] Scanning for projects..."
echo "[INFO] ------------------------------------------------------------------------"
echo "[INFO] Building Payment Service 1.0.4-SNAPSHOT"
echo "[INFO] ------------------------------------------------------------------------"

if [ "$SCENARIO" = "SUCCESS" ]; then
    echo "[INFO] Tests run: 45, Failures: 0, Errors: 0, Skipped: 0"
    echo "[INFO] BUILD SUCCESS"
    exit 0
elif [ "$SCENARIO" = "TIMEOUT" ]; then
    echo "[INFO] Connecting to external gateway..."
    sleep 1
    echo "[ERROR] Failed to execute goal com.example:payment-plugin:1.0:process (default) on project payment-service:"
    echo "[ERROR] java.net.SocketTimeoutException: Read timed out"
    echo "[ERROR]     at java.base/java.net.SocketInputStream.socketRead0(Native Method)"
    echo "[ERROR]     at java.base/java.net.SocketInputStream.socketRead(SocketInputStream.java:115)"
    echo "[ERROR]     at java.base/java.net.SocketInputStream.read(SocketInputStream.java:168)"
    echo "[ERROR]     at java.base/java.net.SocketInputStream.read(SocketInputStream.java:140)"
    echo "[ERROR]     at com.example.gateway.Connection.read(Connection.java:245)"
    echo "[INFO] ------------------------------------------------------------------------"
    echo "[INFO] BUILD FAILURE"
    exit 1
elif [ "$SCENARIO" = "NPE" ]; then
    echo "[INFO] Processing transactions..."
    echo "[ERROR] Unexpected error occurred"
    echo "java.lang.NullPointerException: Cannot invoke \"String.length()\" because \"txnId\" is null"
    echo "    at com.example.service.TransactionProcessor.process(TransactionProcessor.java:56)"
    echo "    at com.example.service.BatchRunner.run(BatchRunner.java:102)"
    echo "[INFO] BUILD FAILURE"
    exit 1
elif [ "$SCENARIO" = "DISK" ]; then
    echo "[INFO] Writing artifacts..."
    echo "java.io.IOException: No space left on device"
    echo "    at java.base/java.io.FileOutputStream.writeBytes(Native Method)"
    echo "    at java.base/java.io.FileOutputStream.write(FileOutputStream.java:349)"
    echo "[INFO] BUILD FAILURE"
    exit 1
fi
      </command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
EOF

# Create job via CLI
jenkins_cli create-job "$JOB_NAME" < /tmp/generator_config.xml

# 2. Generate Randomized Build History
# We will generate 8 builds
TIMEOUT_BUILDS=()

echo "Generating build history (8 builds)..."
for i in {1..8}; do
    # Weighted random selection
    # 0-3: SUCCESS (40%)
    # 4-6: TIMEOUT (30%)
    # 7-8: OTHER (NPE/DISK) (30%)
    RAND=$((RANDOM % 10))
    
    if [ $RAND -lt 4 ]; then
        SCENARIO="SUCCESS"
    elif [ $RAND -lt 7 ]; then
        SCENARIO="TIMEOUT"
        TIMEOUT_BUILDS+=($i)
    elif [ $RAND -lt 9 ]; then
        SCENARIO="NPE"
    else
        SCENARIO="DISK"
    fi
    
    echo "  Build #$i: $SCENARIO"
    
    # Trigger build and wait for it
    # -s waits for completion
    jenkins_cli build "$JOB_NAME" -p SCENARIO="$SCENARIO" -s > /dev/null 2>&1 || true
done

# Save ground truth (comma separated)
IFS=,
echo "${TIMEOUT_BUILDS[*]}" > "$TRUTH_FILE"
unset IFS
echo "Ground Truth: $(cat $TRUTH_FILE)"

# 3. Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Start Firefox focused on the job
echo "Launching Firefox..."
JOB_URL="$JENKINS_URL/job/$JOB_NAME"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$JOB_URL' > /tmp/firefox_task.log 2>&1 &"
else
    # Navigate existing firefox
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        su - ga -c "DISPLAY=:1 firefox -new-window '$JOB_URL' &"
    fi
fi

# Wait for window and maximize
wait_for_window "firefox\|mozilla\|jenkins" 30
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="