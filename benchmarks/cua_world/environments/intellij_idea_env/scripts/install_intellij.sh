#!/bin/bash
set -e

echo "=== Installing IntelliJ IDEA Community Edition ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Java 17 (required for development projects)
echo "Installing OpenJDK 17..."
apt-get install -y \
    openjdk-17-jdk \
    openjdk-17-jre

# Install Maven for Java project builds
echo "Installing Maven..."
apt-get install -y maven

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
    jq

# Set JAVA_HOME
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
echo "JAVA_HOME=$JAVA_HOME" >> /etc/environment

# Download IntelliJ IDEA Community Edition
echo "Downloading IntelliJ IDEA CE..."
IDEA_VERSION="2024.3.1.1"
IDEA_DOWNLOAD_URL="https://download.jetbrains.com/idea/ideaIC-${IDEA_VERSION}.tar.gz"

wget -q "$IDEA_DOWNLOAD_URL" -O /tmp/idea.tar.gz || {
    echo "Failed to download IntelliJ IDEA from primary URL, trying alternate..."
    # Fallback to a slightly different version format
    IDEA_VERSION="2024.3"
    IDEA_DOWNLOAD_URL="https://download.jetbrains.com/idea/ideaIC-${IDEA_VERSION}.tar.gz"
    wget -q "$IDEA_DOWNLOAD_URL" -O /tmp/idea.tar.gz
}

# Extract IntelliJ to /opt/idea
echo "Extracting IntelliJ IDEA..."
mkdir -p /opt/idea
tar -xzf /tmp/idea.tar.gz -C /opt/idea --strip-components=1
rm -f /tmp/idea.tar.gz

# Create symlink for easy access
ln -sf /opt/idea/bin/idea.sh /usr/local/bin/idea

# Verify installation
if [ -f /opt/idea/bin/idea.sh ]; then
    echo "IntelliJ IDEA installed at /opt/idea"
    ls -la /opt/idea/bin/idea.sh
else
    echo "ERROR: IntelliJ IDEA installation failed!"
    exit 1
fi

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
            <version>4.12</version>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>joda-time</groupId>
            <artifactId>joda-time</artifactId>
            <version>2.9.2</version>
        </dependency>
    </dependencies>
</project>
POMEOF

cd /tmp/maven-warmup && mvn dependency:resolve -q 2>/dev/null || true
rm -rf /tmp/maven-warmup

# Clean up apt cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== IntelliJ IDEA installation complete ==="
