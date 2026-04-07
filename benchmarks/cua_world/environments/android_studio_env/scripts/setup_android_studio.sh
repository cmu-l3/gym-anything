#!/bin/bash
set -e

echo "=== Setting up Android Studio ==="

# Wait for desktop to be ready
sleep 5

# Set SDK environment variables
export ANDROID_SDK_ROOT=/opt/android-sdk
export ANDROID_HOME=/opt/android-sdk
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# Determine Android Studio config directory
# Android Studio uses ~/.config/Google/AndroidStudio<version>/ on Linux
# We check the build number to determine the version
BUILD_NUM=""
if [ -f /opt/android-studio/build.txt ]; then
    BUILD_NUM=$(cat /opt/android-studio/build.txt | head -1)
    echo "Android Studio build: $BUILD_NUM"
fi

# Parse version from build: AI-242.23339.11.2421.12483815 -> 2024.2
STUDIO_MAJOR=$(echo "$BUILD_NUM" | grep -oP '(?<=AI-)\d+' || echo "242")
if [ -n "$STUDIO_MAJOR" ] && [ "$STUDIO_MAJOR" -gt 0 ] 2>/dev/null; then
    YEAR=$((STUDIO_MAJOR / 10 + 2000))
    MINOR=$((STUDIO_MAJOR % 10))
    STUDIO_VERSION_SHORT="${YEAR}.${MINOR}"
else
    STUDIO_VERSION_SHORT="2024.2"
fi
STUDIO_DIR_NAME="AndroidStudio${STUDIO_VERSION_SHORT}"
echo "Using config directory name: $STUDIO_DIR_NAME"

# Create Android Studio config directories for user ga
su - ga -c "mkdir -p /home/ga/.config/Google/${STUDIO_DIR_NAME}"
su - ga -c "mkdir -p /home/ga/.cache/Google/${STUDIO_DIR_NAME}"
su - ga -c "mkdir -p /home/ga/.local/share/Google/${STUDIO_DIR_NAME}"

# Suppress data sharing consent dialog
su - ga -c "mkdir -p /home/ga/.config/Google/consentOptions"
su - ga -c "echo 'rsch.send.usage.stat:1.1:0:\$(date +%s)000' > /home/ga/.config/Google/consentOptions/accepted"

# Pre-accept EULA
EULA_DIR="/home/ga/.config/Google/${STUDIO_DIR_NAME}"
mkdir -p "${EULA_DIR}"

cat > "${EULA_DIR}/accepted" << 'EULAEOF'
jetbrains.privacy.policy.accepted=true
eua.accepted=true
EULAEOF

# Set privacy policy via Java Preferences
mkdir -p "/home/ga/.java/.userPrefs/jetbrains/_!(!)!'-sym!"
cat > "/home/ga/.java/.userPrefs/jetbrains/_!(!)!'-sym!/prefs.xml" << 'PREFSEOF'
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<!DOCTYPE map SYSTEM "http://java.sun.com/dtd/preferences.dtd">
<map MAP_XML_VERSION="1.0">
  <entry key="user_agreement_accepted_version" value="2.1"/>
  <entry key="eua_accepted_version" value="2.1"/>
  <entry key="privacy_policy_accepted_version" value="2.1"/>
</map>
PREFSEOF
chown -R ga:ga /home/ga/.java 2>/dev/null || true

# Suppress initial config dialog
cat > "${EULA_DIR}/idea.properties" << 'PROPSEOF'
idea.initially.ask.config=false
PROPSEOF

# Set custom VM options
cat > /home/ga/.config/Google/${STUDIO_DIR_NAME}/studio64.vmoptions << 'VMOPTS'
-Xms512m
-Xmx2048m
-XX:ReservedCodeCacheSize=512m
-Dnosplash=true
-Djb.privacy.policy.text=<!--999.999-->
-Djb.consents.confirmation.enabled=false
-Didea.initially.ask.config=false
VMOPTS
chown ga:ga /home/ga/.config/Google/${STUDIO_DIR_NAME}/studio64.vmoptions

# Disable tip of the day
mkdir -p /home/ga/.config/Google/${STUDIO_DIR_NAME}/options
cat > /home/ga/.config/Google/${STUDIO_DIR_NAME}/options/ide.general.xml << 'IDEOPTS'
<application>
  <component name="GeneralSettings">
    <option name="showTipsOnStartup" value="false" />
    <option name="confirmExit" value="false" />
  </component>
</application>
IDEOPTS
chown ga:ga /home/ga/.config/Google/${STUDIO_DIR_NAME}/options/ide.general.xml

# Pre-configure trusted paths
cat > /home/ga/.config/Google/${STUDIO_DIR_NAME}/options/trusted-paths.xml << 'TRUSTXML'
<application>
  <component name="TrustedPathsSettings">
    <option name="trustedPaths">
      <list>
        <option value="/home/ga/AndroidStudioProjects" />
        <option value="/home/ga" />
        <option value="/workspace" />
        <option value="/tmp" />
      </list>
    </option>
    <option name="TRUSTED_PROJECT_PATHS">
      <map>
        <entry key="/home/ga/AndroidStudioProjects" value="true" />
        <entry key="/home/ga" value="true" />
        <entry key="/workspace" value="true" />
      </map>
    </option>
  </component>
  <component name="Trusted.Paths.Settings">
    <option name="TRUSTED_PATHS">
      <list>
        <option value="/home/ga/AndroidStudioProjects" />
        <option value="/home/ga" />
        <option value="/workspace" />
      </list>
    </option>
  </component>
</application>
TRUSTXML
chown ga:ga /home/ga/.config/Google/${STUDIO_DIR_NAME}/options/trusted-paths.xml

# Configure trusted projects
cat > /home/ga/.config/Google/${STUDIO_DIR_NAME}/options/trustedProjects.xml << 'TRUSTEDPROJ'
<application>
  <component name="TrustedProjects">
    <option name="trustedProjects">
      <list>
        <option value="/home/ga/AndroidStudioProjects" />
        <option value="/home/ga/AndroidStudioProjects/SunflowerApp" />
        <option value="/home/ga/AndroidStudioProjects/BrokenApp" />
        <option value="/home/ga/AndroidStudioProjects/NotepadApp" />
        <option value="/home/ga/AndroidStudioProjects/CalculatorApp" />
        <option value="/workspace" />
      </list>
    </option>
  </component>
</application>
TRUSTEDPROJ
chown ga:ga /home/ga/.config/Google/${STUDIO_DIR_NAME}/options/trustedProjects.xml

# Configure Android SDK path for Android Studio
mkdir -p /home/ga/.config/Google/${STUDIO_DIR_NAME}
cat > /home/ga/.config/Google/${STUDIO_DIR_NAME}/options/android-settings.xml << 'ANDROIDXML'
<application>
  <component name="AndroidSdkPathSettings">
    <option name="androidSdkPath" value="/opt/android-sdk" />
  </component>
</application>
ANDROIDXML
chown ga:ga /home/ga/.config/Google/${STUDIO_DIR_NAME}/options/android-settings.xml

# Configure JDK in Android Studio
cat > /home/ga/.config/Google/${STUDIO_DIR_NAME}/options/jdk.table.xml << 'JDKXML'
<application>
  <component name="ProjectJdkTable">
    <jdk version="2">
      <name value="17" />
      <type value="JavaSDK" />
      <version value="java version &quot;17&quot;" />
      <homePath value="/usr/lib/jvm/java-17-openjdk-amd64" />
      <roots>
        <annotationsPath>
          <root type="composite" />
        </annotationsPath>
        <classPath>
          <root type="composite">
            <root url="jar:///usr/lib/jvm/java-17-openjdk-amd64/lib/jrt-fs.jar!/" type="simple" />
          </root>
        </classPath>
        <javadocPath>
          <root type="composite" />
        </javadocPath>
        <sourcePath>
          <root type="composite" />
        </sourcePath>
      </roots>
    </jdk>
  </component>
</application>
JDKXML
chown ga:ga /home/ga/.config/Google/${STUDIO_DIR_NAME}/options/jdk.table.xml

# Set ownership of all config
chown -R ga:ga /home/ga/.config/Google
chown -R ga:ga /home/ga/.cache/Google 2>/dev/null || true
chown -R ga:ga /home/ga/.local/share/Google 2>/dev/null || true

# Create project directory
su - ga -c "mkdir -p /home/ga/AndroidStudioProjects"

# Create Android SDK config for ga user
su - ga -c "mkdir -p /home/ga/.android"
su - ga -c "touch /home/ga/.android/repositories.cfg"

# Configure Git for ga user
su - ga -c "git config --global user.name 'ga'"
su - ga -c "git config --global user.email 'ga@localhost'"
su - ga -c "git config --global init.defaultBranch main"

# Set environment variables in ga's bashrc
cat >> /home/ga/.bashrc << 'ENVEOF'
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export ANDROID_SDK_ROOT=/opt/android-sdk
export ANDROID_HOME=/opt/android-sdk
export PATH=$JAVA_HOME/bin:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH
export PATH=/opt/android-studio/bin:$PATH
ENVEOF

# CRITICAL: Also set environment variables system-wide so that Gradle
# subprocesses, Android Studio internal builds, and non-login shells
# can reliably find the Android SDK. .bashrc alone is not sufficient.
cat > /etc/profile.d/android-sdk.sh << 'PROFILEEOF'
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export ANDROID_SDK_ROOT=/opt/android-sdk
export ANDROID_HOME=/opt/android-sdk
export PATH=$JAVA_HOME/bin:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH
export PATH=/opt/android-studio/bin:$PATH
PROFILEEOF
chmod +x /etc/profile.d/android-sdk.sh

# Also add to /etc/environment for PAM-based session loading
# (covers GUI sessions, su - , etc.)
grep -q 'ANDROID_SDK_ROOT' /etc/environment 2>/dev/null || cat >> /etc/environment << 'ETCENVEOF'
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ANDROID_SDK_ROOT=/opt/android-sdk
ANDROID_HOME=/opt/android-sdk
ETCENVEOF

# Write local.properties with sdk.dir into all known project directories
# so Gradle can find the SDK even without environment variables.
for proj_dir in /workspace/data/SunflowerApp /workspace/data/BrokenApp \
                /workspace/data/NotepadApp /workspace/data/CalculatorApp; do
    if [ -d "$proj_dir" ]; then
        echo "sdk.dir=/opt/android-sdk" > "$proj_dir/local.properties"
        echo "  Wrote local.properties to $proj_dir"
    fi
done

# Create desktop launcher
cat > /home/ga/Desktop/AndroidStudio.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Android Studio
Comment=Android Studio IDE
Exec=/opt/android-studio/bin/studio.sh
Icon=/opt/android-studio/bin/studio.svg
StartupNotify=true
Terminal=false
Type=Application
Categories=Development;IDE;
DESKTOPEOF
chmod +x /home/ga/Desktop/AndroidStudio.desktop
chown ga:ga /home/ga/Desktop/AndroidStudio.desktop

# Launch Android Studio
echo "Launching Android Studio..."
su - ga -c "export DISPLAY=:1; export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; export ANDROID_SDK_ROOT=/opt/android-sdk; export ANDROID_HOME=/opt/android-sdk; nohup /opt/android-studio/bin/studio.sh > /tmp/android_studio_startup.log 2>&1 &"

# Give a moment for the process to detach
sleep 2

# Wait for Android Studio window to appear
echo "Waiting for Android Studio to start..."
STUDIO_STARTED=false
for i in $(seq 1 120); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "android\|studio\|welcome"; then
        STUDIO_STARTED=true
        echo "Android Studio window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$STUDIO_STARTED" = true ]; then
    sleep 5

    # Maximize the window
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "android\|studio\|welcome" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        echo "Android Studio window maximized"
    fi

    # Dismiss any remaining startup dialogs
    sleep 3
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
else
    echo "WARNING: Android Studio window not detected within 120 seconds"
    echo "Check /tmp/android_studio_startup.log for details"
fi

echo "=== Android Studio setup complete ==="
