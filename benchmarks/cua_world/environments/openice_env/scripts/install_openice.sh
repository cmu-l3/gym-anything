#!/bin/bash
set -e

echo "=== Installing OpenICE (Open-source Integrated Clinical Environment) ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Java 17 (required by OpenICE 2.0)
echo "=== Installing Java 17 ==="
apt-get install -y openjdk-17-jdk openjdk-17-jre

# Set JAVA_HOME
echo "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64" >> /etc/environment
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# Install required dependencies for JavaFX GUI
echo "=== Installing JavaFX and GUI dependencies ==="
apt-get install -y \
    libgtk-3-0 \
    libgl1-mesa-glx \
    libgl1-mesa-dri \
    libasound2 \
    libxrender1 \
    libxtst6 \
    libxi6 \
    libxslt1.1 \
    libxxf86vm1 \
    fonts-dejavu \
    fonts-liberation

# Install build tools
echo "=== Installing build tools ==="
apt-get install -y \
    git \
    wget \
    curl \
    unzip

# Install GUI automation tools
echo "=== Installing GUI automation tools ==="
apt-get install -y \
    wmctrl \
    xdotool \
    x11-utils \
    scrot \
    imagemagick

# Install Python for verification scripts
apt-get install -y \
    python3 \
    python3-pip \
    python3-pillow

# Create OpenICE directory
mkdir -p /opt/openice
mkdir -p /home/ga/openice

# Clone OpenICE repository
echo "=== Cloning OpenICE repository ==="
cd /opt/openice
if [ ! -d "mdpnp" ]; then
    git clone --depth 1 https://github.com/mdpnp/mdpnp.git
fi

# Set ownership
chown -R ga:ga /opt/openice
chown -R ga:ga /home/ga/openice

# Make gradlew executable
chmod +x /opt/openice/mdpnp/gradlew

# Skip full pre-build to avoid timeout issues - just download gradle wrapper
# The full build will happen on first run in setup_openice.sh
echo "=== Downloading Gradle wrapper (skipping full build for faster install) ==="
cd /opt/openice/mdpnp
# Just verify gradlew runs and downloads the wrapper
su - ga -c "cd /opt/openice/mdpnp && ./gradlew --version" || {
    echo "Warning: Gradle wrapper download had issues"
}

# Create launch script
cat > /usr/local/bin/openice << 'EOF'
#!/bin/bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export DISPLAY=${DISPLAY:-:1}
cd /opt/openice/mdpnp
./gradlew :interop-lab:demo-apps:run --no-daemon "$@"
EOF
chmod +x /usr/local/bin/openice

# Create desktop shortcut
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/OpenICE.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=OpenICE
Comment=Open-source Integrated Clinical Environment
Exec=/usr/local/bin/openice
Icon=applications-science
Terminal=false
Categories=Science;Medical;
StartupNotify=true
EOF
chmod +x /home/ga/Desktop/OpenICE.desktop
chown ga:ga /home/ga/Desktop/OpenICE.desktop

echo "=== OpenICE installation complete ==="
echo "Java version:"
java -version
echo "OpenICE location: /opt/openice/mdpnp"
