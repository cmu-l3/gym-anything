#!/bin/bash
set -e

echo "=== Installing OpenRocket ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Java 17 (required to run OpenRocket JAR)
apt-get install -y \
    openjdk-17-jdk \
    openjdk-17-jre

# Set JAVA_HOME system-wide
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
echo "JAVA_HOME=$JAVA_HOME" >> /etc/environment

# Install GUI automation tools
apt-get install -y \
    wget curl ca-certificates \
    xdotool wmctrl x11-utils xclip \
    imagemagick scrot \
    python3-pip jq unzip libfuse2

# Download OpenRocket JAR (platform-independent, version 24.12)
echo "Downloading OpenRocket 24.12..."
OPENROCKET_URL="https://github.com/openrocket/openrocket/releases/download/release-24.12/OpenRocket-24.12.jar"
OPENROCKET_DIR="/opt/openrocket"
mkdir -p "$OPENROCKET_DIR"

wget -q "$OPENROCKET_URL" -O "$OPENROCKET_DIR/OpenRocket.jar" || {
    echo "Primary download failed, trying alternate version 23.09..."
    OPENROCKET_URL="https://github.com/openrocket/openrocket/releases/download/release-23.09/OpenRocket-23.09.jar"
    wget -q "$OPENROCKET_URL" -O "$OPENROCKET_DIR/OpenRocket.jar"
}

# Verify download
if [ ! -f "$OPENROCKET_DIR/OpenRocket.jar" ]; then
    echo "ERROR: OpenRocket download failed!"
    exit 1
fi

echo "OpenRocket JAR downloaded: $(ls -lh $OPENROCKET_DIR/OpenRocket.jar)"

# Create launch wrapper script
cat > /usr/local/bin/openrocket << 'LAUNCHEOF'
#!/bin/bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export DISPLAY="${DISPLAY:-:1}"
exec java -Xms512m -Xmx2048m -jar /opt/openrocket/OpenRocket.jar "$@"
LAUNCHEOF
chmod +x /usr/local/bin/openrocket

# Download real .ork rocket design files for tasks
echo "=== Downloading real rocket design files ==="
ROCKETS_DIR="/home/ga/Documents/rockets"
mkdir -p "$ROCKETS_DIR"

# Official OpenRocket example rockets (from GitHub repository)
EXAMPLES_BASE="https://raw.githubusercontent.com/openrocket/openrocket/master/core/src/main/resources/datafiles/examples"

wget -q "${EXAMPLES_BASE}/A%20simple%20model%20rocket.ork" -O "$ROCKETS_DIR/simple_model_rocket.ork" || true
wget -q "${EXAMPLES_BASE}/Two%20stage%20high%20power%20rocket.ork" -O "$ROCKETS_DIR/two_stage_high_power_rocket.ork" || true
wget -q "${EXAMPLES_BASE}/Three%20stage%20low%20power%20rocket.ork" -O "$ROCKETS_DIR/three_stage_low_power_rocket.ork" || true
wget -q "${EXAMPLES_BASE}/Dual%20parachute%20deployment.ork" -O "$ROCKETS_DIR/dual_parachute_deployment.ork" || true
wget -q "${EXAMPLES_BASE}/Clustered%20motors.ork" -O "$ROCKETS_DIR/clustered_motors.ork" || true
wget -q "${EXAMPLES_BASE}/Tube%20fin%20rocket.ork" -O "$ROCKETS_DIR/tube_fin_rocket.ork" || true
wget -q "${EXAMPLES_BASE}/Parallel%20booster%20staging.ork" -O "$ROCKETS_DIR/parallel_booster_staging.ork" || true
wget -q "${EXAMPLES_BASE}/Chute%20release.ork" -O "$ROCKETS_DIR/chute_release.ork" || true

# Real university team rockets (from RocketPy-Team/RocketSerializer)
ROCKETPY_BASE="https://raw.githubusercontent.com/RocketPy-Team/RocketSerializer/master/examples"
wget -q "${ROCKETPY_BASE}/EPFL--BellaLui--2020/rocket.ork" -O "$ROCKETS_DIR/EPFL_BellaLui_2020.ork" || true
wget -q "${ROCKETPY_BASE}/NDRT--Rocket--2020/rocket.ork" -O "$ROCKETS_DIR/NDRT_Rocket_2020.ork" || true
wget -q "${ROCKETPY_BASE}/ProjetoJupiter--Valetudo--2019/rocket.ork" -O "$ROCKETS_DIR/ProjetoJupiter_Valetudo_2019.ork" || true

# 3D-printable rocket designs
wget -q "https://raw.githubusercontent.com/3dp-rocket/rockets/master/janus/OpenRocket-29mm.ork" -O "$ROCKETS_DIR/janus_29mm.ork" || true
wget -q "https://raw.githubusercontent.com/3dp-rocket/rockets/master/janus/OpenRocket-38mm.ork" -O "$ROCKETS_DIR/janus_38mm.ork" || true

# Count downloaded files
ROCKET_COUNT=$(ls "$ROCKETS_DIR"/*.ork 2>/dev/null | wc -l)
echo "Downloaded $ROCKET_COUNT .ork rocket design files"

# Also copy from mounted workspace data as backup
if [ -d /workspace/data/rockets ]; then
    cp -n /workspace/data/rockets/*.ork "$ROCKETS_DIR/" 2>/dev/null || true
    echo "Copied additional rockets from workspace data"
fi

# Set ownership
chown -R ga:ga "$ROCKETS_DIR"
chown -R ga:ga /home/ga/Documents

# Verify Java and OpenRocket
echo "=== Verification ==="
java -version 2>&1
echo "OpenRocket JAR: $(ls -lh $OPENROCKET_DIR/OpenRocket.jar)"
echo "Rocket files: $(ls $ROCKETS_DIR/*.ork 2>/dev/null | wc -l) designs"

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== OpenRocket installation complete ==="
