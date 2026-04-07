#!/bin/bash
# Note: deliberately NOT using set -e to prevent early exit on non-critical failures

echo "=== Setting up OpenICE ==="

# Wait for desktop to be ready
sleep 5

# Wait for desktop file to be fully synced before trusting
sleep 2

# Mark desktop shortcut as trusted to prevent GNOME "Untrusted Desktop File" dialog
su - ga -c "dbus-launch gio set /home/ga/Desktop/OpenICE.desktop metadata::trusted true" 2>/dev/null || true

# Fallback: set trusted attribute via python3 gio
su - ga -c "python3 -c \"import subprocess; subprocess.run(['gio', 'set', '/home/ga/Desktop/OpenICE.desktop', 'metadata::trusted', 'true'])\"" 2>/dev/null || true

# Fallback: clear immutable flag if set
chattr -i /home/ga/Desktop/OpenICE.desktop 2>/dev/null || true

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

# Fix Gradle repositories: build.openice.info is often unreachable.
# Add pluginManagement block to settings.gradle AND fix buildscript repos
# in demo-apps/build.gradle so Gradle resolves plugins and dependencies
# from the Gradle Plugin Portal and Maven Central as fallbacks.
if ! grep -q "pluginManagement" /opt/openice/mdpnp/settings.gradle 2>/dev/null; then
    echo "=== Adding fallback Gradle plugin repositories to settings.gradle ==="
    sed -i '1i\pluginManagement {\n    repositories {\n        gradlePluginPortal()\n        mavenCentral()\n        maven { url = "https://build.openice.info/artifactory/remote-repos" }\n    }\n}\n' /opt/openice/mdpnp/settings.gradle
    chown ga:ga /opt/openice/mdpnp/settings.gradle
fi

# Also fix the buildscript repositories in demo-apps/build.gradle
DEMO_BUILD="/opt/openice/mdpnp/interop-lab/demo-apps/build.gradle"
if ! grep -q "gradlePluginPortal()" "$DEMO_BUILD" 2>/dev/null; then
    echo "=== Adding fallback buildscript repositories to demo-apps/build.gradle ==="
    sed -i '/^    repositories {/a\        gradlePluginPortal()\n        mavenCentral()' "$DEMO_BUILD"
    chown ga:ga "$DEMO_BUILD"
fi

# Fix audio crash: PCAPanel and RBSPanel try to initialize audio clips for
# alarm sounds, but the VM has no audio hardware. The catch blocks miss
# IllegalArgumentException, causing the Infusion Safety and Rule-Based
# Safety apps to silently fail to load. Add the missing catch clause.
PCA_PANEL="/opt/openice/mdpnp/interop-lab/demo-apps/src/main/java/org/mdpnp/apps/testapp/pca/PCAPanel.java"
RBS_PANEL="/opt/openice/mdpnp/interop-lab/demo-apps/src/main/java/org/mdpnp/apps/testapp/rbs/RBSPanel.java"
for PANEL_FILE in "$PCA_PANEL" "$RBS_PANEL"; do
    if [ -f "$PANEL_FILE" ] && ! grep -q "IllegalArgumentException" "$PANEL_FILE" 2>/dev/null; then
        echo "=== Fixing audio exception handling in $(basename $PANEL_FILE) ==="
        sed -i 's/} catch (LineUnavailableException e) {/} catch (LineUnavailableException e) {\n            e.printStackTrace();\n        } catch (IllegalArgumentException e) {/' "$PANEL_FILE"
        chown ga:ga "$PANEL_FILE"
        # Force rebuild
        rm -rf /opt/openice/mdpnp/interop-lab/demo-apps/build/classes 2>/dev/null || true
    fi
done

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
# Use nohup to prevent SIGHUP from killing the process when parent shell exits
nohup ./gradlew :interop-lab:demo-apps:run --no-daemon > /home/ga/openice/logs/openice.log 2>&1 &
disown
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
su - ga -c "cd /home/ga/openice && DISPLAY=:1 nohup ./launch_supervisor.sh > /dev/null 2>&1" &

# Wait for OpenICE to start (Java/Gradle startup can take a while)
echo "=== Waiting for OpenICE to start ==="
MAX_WAIT=300
ELAPSED=0
OPENICE_STARTED=false

while [ $ELAPSED -lt $MAX_WAIT ]; do
    # Check if any Java process with demo-apps or gradlew is running
    if pgrep -f "java.*(demo-apps|openice)|gradlew.*demo-apps" > /dev/null 2>&1; then
        echo "OpenICE Java process detected"
        # Wait a bit more for GUI to appear
        sleep 15

        # Check for window
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "openice|ice|supervisor|demo|medical" > /dev/null 2>&1; then
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
