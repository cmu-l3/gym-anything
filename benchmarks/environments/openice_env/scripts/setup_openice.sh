#!/bin/bash
set -e

echo "=== Setting up OpenICE ==="

# Wait for desktop to be ready
sleep 5

# Ensure JAVA_HOME is set
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export DISPLAY=:1

# Set memory limits for Gradle to prevent OOM
export GRADLE_OPTS="-Xmx2g -XX:MaxMetaspaceSize=512m"

# Check Java installation
echo "=== Verifying Java installation ==="
java -version

# Ensure OpenICE directory has correct permissions
chown -R ga:ga /opt/openice
chown -R ga:ga /home/ga/openice

# Create workspace directories
mkdir -p /home/ga/openice/logs
mkdir -p /home/ga/openice/data
chown -R ga:ga /home/ga/openice

# Build OpenICE if not already built (this may take a while on first run)
echo "=== Building OpenICE (first run may take several minutes) ==="
cd /opt/openice/mdpnp

if [ ! -d "interop-lab/demo-apps/build/classes" ]; then
    echo "Building OpenICE for the first time..."
    # Build with timeout to prevent hanging
    timeout 600 su - ga -c "cd /opt/openice/mdpnp && JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 GRADLE_OPTS='-Xmx2g' ./gradlew :interop-lab:demo-apps:classes --no-daemon" 2>&1 | tee /home/ga/openice/logs/build.log || {
        echo "Warning: Build had issues or timed out, attempting to continue..."
    }
else
    echo "OpenICE already built, skipping..."
fi

# Create a simpler launch script for the supervisor
cat > /home/ga/openice/launch_supervisor.sh << 'EOF'
#!/bin/bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export DISPLAY=:1
export GRADLE_OPTS="-Xmx2g"
cd /opt/openice/mdpnp
./gradlew :interop-lab:demo-apps:run --no-daemon 2>&1 | tee /home/ga/openice/logs/openice.log &
EOF
chmod +x /home/ga/openice/launch_supervisor.sh
chown ga:ga /home/ga/openice/launch_supervisor.sh

# Create a script to check if OpenICE window is running
cat > /home/ga/openice/check_running.sh << 'EOF'
#!/bin/bash
export DISPLAY=:1
# Check if OpenICE window exists
if wmctrl -l 2>/dev/null | grep -iE "openice|ice.+supervisor|demo-apps" > /dev/null 2>&1; then
    echo "OpenICE is running"
    exit 0
else
    echo "OpenICE is not running"
    exit 1
fi
EOF
chmod +x /home/ga/openice/check_running.sh
chown ga:ga /home/ga/openice/check_running.sh

# Start OpenICE in background
echo "=== Starting OpenICE Supervisor ==="
su - ga -c "cd /home/ga/openice && DISPLAY=:1 ./launch_supervisor.sh" &

# Wait for OpenICE to start (Java/Gradle startup can take a while)
echo "=== Waiting for OpenICE to start ==="
MAX_WAIT=300
ELAPSED=0
OPENICE_STARTED=false

while [ $ELAPSED -lt $MAX_WAIT ]; do
    # Check if any Java process with demo-apps or gradlew is running
    if pgrep -f "java.*demo-apps\|java.*openice\|gradlew.*demo-apps" > /dev/null 2>&1; then
        echo "OpenICE Java process detected"
        # Wait a bit more for GUI to appear
        sleep 15

        # Check for window
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "openice\|ice\|supervisor\|demo\|medical" > /dev/null 2>&1; then
            echo "OpenICE window detected!"
            OPENICE_STARTED=true
            break
        fi
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
    echo "Waiting for OpenICE... ($ELAPSED/$MAX_WAIT seconds)"
done

if [ "$OPENICE_STARTED" = "true" ]; then
    echo "=== OpenICE started successfully ==="
    # Maximize the window
    sleep 3
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
else
    echo "Warning: OpenICE may not have started completely within timeout"
    echo "Check logs at /home/ga/openice/logs/openice.log"
    echo "Build logs at /home/ga/openice/logs/build.log"
fi

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/openice_setup_complete.png 2>/dev/null || true

echo "=== OpenICE setup complete ==="
echo "Logs: /home/ga/openice/logs/openice.log"
