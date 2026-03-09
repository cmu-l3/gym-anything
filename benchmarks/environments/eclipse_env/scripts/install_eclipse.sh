#!/bin/bash
set -e

echo "=== Installing Eclipse IDE ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Java 17 (required for development projects)
echo "Installing OpenJDK 17..."
apt-get install -y \
    openjdk-17-jdk \
    openjdk-17-jre

# Install Maven and Gradle for Java project builds
echo "Installing Maven and Gradle..."
apt-get install -y maven gradle

# Install GUI automation and utility tools
apt-get install -y \
    wget \
    curl \
    ca-certificates \
    xdotool \
    wmctrl \
    x11-utils \
    xclip \
    imagemagick \
    scrot \
    git \
    python3-pip \
    jq \
    unzip

# Set JAVA_HOME
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
echo "JAVA_HOME=$JAVA_HOME" >> /etc/environment

# Download Eclipse IDE for Java Developers
echo "Downloading Eclipse IDE..."
ECLIPSE_VERSION="2024-12"
ECLIPSE_DOWNLOAD_URL="https://www.eclipse.org/downloads/download.php?file=/technology/epp/downloads/release/${ECLIPSE_VERSION}/R/eclipse-java-${ECLIPSE_VERSION}-R-linux-gtk-x86_64.tar.gz&r=1"

# Try primary download URL
wget -q --content-disposition -O /tmp/eclipse.tar.gz "$ECLIPSE_DOWNLOAD_URL" || {
    echo "Failed to download from primary URL, trying mirror..."
    # Fallback to direct mirror
    wget -q -O /tmp/eclipse.tar.gz "https://mirror.umd.edu/eclipse/technology/epp/downloads/release/${ECLIPSE_VERSION}/R/eclipse-java-${ECLIPSE_VERSION}-R-linux-gtk-x86_64.tar.gz" || {
        echo "Trying another mirror..."
        # Another fallback
        wget -q -O /tmp/eclipse.tar.gz "https://ftp.fau.de/eclipse/technology/epp/downloads/release/${ECLIPSE_VERSION}/R/eclipse-java-${ECLIPSE_VERSION}-R-linux-gtk-x86_64.tar.gz" || {
            echo "Trying 2024-09 version..."
            ECLIPSE_VERSION="2024-09"
            wget -q -O /tmp/eclipse.tar.gz "https://mirror.umd.edu/eclipse/technology/epp/downloads/release/${ECLIPSE_VERSION}/R/eclipse-java-${ECLIPSE_VERSION}-R-linux-gtk-x86_64.tar.gz"
        }
    }
}

# Extract Eclipse to /opt/eclipse
echo "Extracting Eclipse IDE..."
mkdir -p /opt/eclipse
tar -xzf /tmp/eclipse.tar.gz -C /opt --strip-components=0
rm -f /tmp/eclipse.tar.gz

# Verify installation
if [ -f /opt/eclipse/eclipse ]; then
    echo "Eclipse IDE installed at /opt/eclipse"
    ls -la /opt/eclipse/eclipse
else
    echo "ERROR: Eclipse IDE installation failed!"
    exit 1
fi

# Create symlink for easy access
ln -sf /opt/eclipse/eclipse /usr/local/bin/eclipse

# Verify Java installation
java -version 2>&1 || echo "WARNING: Java not accessible"
mvn --version 2>&1 || echo "WARNING: Maven not accessible"

# Pre-download Maven dependencies for common tasks (speeds up task execution)
echo "Pre-warming Maven local repository..."
mkdir -p /tmp/maven-warmup
cat > /tmp/maven-warmup/pom.xml << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.warmup</groupId>
    <artifactId>maven-warmup</artifactId>
    <version>1.0</version>
    <dependencies>
        <dependency>
            <groupId>junit</groupId>
            <artifactId>junit</artifactId>
            <version>4.13.2</version>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>5.10.0</version>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>joda-time</groupId>
            <artifactId>joda-time</artifactId>
            <version>2.12.5</version>
        </dependency>
    </dependencies>
</project>
POMEOF

cd /tmp/maven-warmup && mvn dependency:resolve -q 2>/dev/null || true
rm -rf /tmp/maven-warmup

# Clean up apt cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Eclipse IDE installation complete ==="
