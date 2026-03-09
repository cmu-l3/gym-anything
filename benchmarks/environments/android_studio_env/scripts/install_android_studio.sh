#!/bin/bash
set -e

echo "=== Installing Android Studio ==="

# Non-interactive apt - suppress all interactive prompts
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export NEEDRESTART_MODE=l
export APT_LISTCHANGES_FRONTEND=none

# Configure needrestart to not restart services automatically
mkdir -p /etc/needrestart/conf.d
cat > /etc/needrestart/conf.d/99-noninteractive.conf <<'NEEDRESTART_EOF'
$nrconf{restart} = 'l';
$nrconf{ui} = 'stdio';
$nrconf{kernelhints} = 0;
NEEDRESTART_EOF

# Update package lists
apt-get update -y

# Enable 32-bit architecture (required for Android SDK tools)
dpkg --add-architecture i386
apt-get update -y

# APT options to prevent interactive prompts
APT_OPTS="-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# Install Java 17 (required for Android Gradle Plugin 8.x)
echo "Installing OpenJDK 17..."
apt-get install -y $APT_OPTS \
    openjdk-17-jdk \
    openjdk-17-jre

# Install 32-bit libraries required by Android SDK
apt-get install -y $APT_OPTS \
    libc6:i386 \
    libncurses5:i386 \
    libstdc++6:i386 \
    lib32z1 \
    libbz2-1.0:i386

# Install GUI automation and utility tools
apt-get install -y $APT_OPTS \
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
    unzip \
    fontconfig \
    libfreetype6 \
    libxi6 \
    libxrender1 \
    libxtst6

# Restart SSH if needed to ensure it's running after package installs
systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
sleep 2

# Set JAVA_HOME
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
echo "JAVA_HOME=$JAVA_HOME" >> /etc/environment

# Download Android Studio IDE
echo "Downloading Android Studio..."
STUDIO_VERSION="2024.2.1.11"
STUDIO_DOWNLOAD_URL="https://redirector.gvt1.com/edgedl/android/studio/ide-zips/${STUDIO_VERSION}/android-studio-${STUDIO_VERSION}-linux.tar.gz"

wget -q "$STUDIO_DOWNLOAD_URL" -O /tmp/android-studio.tar.gz || {
    echo "Primary download failed, trying alternate URL..."
    # Fallback: try the direct CDN
    STUDIO_DOWNLOAD_URL="https://dl.google.com/dl/android/studio/ide-zips/${STUDIO_VERSION}/android-studio-${STUDIO_VERSION}-linux.tar.gz"
    wget -q "$STUDIO_DOWNLOAD_URL" -O /tmp/android-studio.tar.gz || {
        echo "Second attempt failed, trying latest stable..."
        # Fallback to generic latest stable URL
        wget -q "https://redirector.gvt1.com/edgedl/android/studio/ide-zips/2024.2.1.11/android-studio-2024.2.1.11-linux.tar.gz" -O /tmp/android-studio.tar.gz
    }
}

# Extract Android Studio to /opt
echo "Extracting Android Studio..."
tar -xzf /tmp/android-studio.tar.gz -C /opt/
rm -f /tmp/android-studio.tar.gz

# Verify Android Studio installation
if [ -f /opt/android-studio/bin/studio.sh ]; then
    echo "Android Studio installed at /opt/android-studio"
    ls -la /opt/android-studio/bin/studio.sh
else
    echo "ERROR: Android Studio installation failed!"
    exit 1
fi

# Create symlink for easy access
ln -sf /opt/android-studio/bin/studio.sh /usr/local/bin/studio

# Disable first-run wizard
echo "disable.android.first.run=true" >> /opt/android-studio/bin/idea.properties

# Install Android SDK via command-line tools
echo "Setting up Android SDK..."
export ANDROID_SDK_ROOT=/opt/android-sdk
mkdir -p $ANDROID_SDK_ROOT/cmdline-tools

# Download command-line tools
wget -q "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" -O /tmp/cmdline-tools.zip || {
    echo "Command-line tools download failed, trying alternate..."
    wget -q "https://dl.google.com/android/repository/commandlinetools-linux-10406996_latest.zip" -O /tmp/cmdline-tools.zip
}

unzip -q /tmp/cmdline-tools.zip -d $ANDROID_SDK_ROOT/cmdline-tools/
mv $ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools $ANDROID_SDK_ROOT/cmdline-tools/latest
rm -f /tmp/cmdline-tools.zip

# Set SDK environment
export PATH=$PATH:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools

# Accept SDK licenses non-interactively
echo "Accepting SDK licenses..."
mkdir -p $ANDROID_SDK_ROOT/licenses
echo -e "\n24333f8a63b6825ea9c5514f83c2829b004d1fee" > $ANDROID_SDK_ROOT/licenses/android-sdk-license
echo -e "\nd975f751698a77e662f1cd747457a47e13b58f7b" >> $ANDROID_SDK_ROOT/licenses/android-sdk-license
echo -e "\n84831b9409646a918e30573bab4c9c91346d8abd" > $ANDROID_SDK_ROOT/licenses/android-sdk-preview-license
yes | $ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager --sdk_root=$ANDROID_SDK_ROOT --licenses 2>/dev/null || true

# Install essential SDK components
echo "Installing SDK components..."
$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager --sdk_root=$ANDROID_SDK_ROOT \
    "platform-tools" \
    "platforms;android-34" \
    "build-tools;34.0.0" \
    "cmdline-tools;latest"

# Set SDK permissions
chown -R root:root $ANDROID_SDK_ROOT
chmod -R 755 $ANDROID_SDK_ROOT

# Create Android user preferences
mkdir -p /root/.android
touch /root/.android/repositories.cfg

# Verify SDK installation
echo "Verifying SDK installation..."
java -version 2>&1 || echo "WARNING: Java not accessible"
$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager --sdk_root=$ANDROID_SDK_ROOT --list 2>/dev/null | head -20 || echo "WARNING: sdkmanager not working"

# Clean up apt cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Android Studio installation complete ==="
