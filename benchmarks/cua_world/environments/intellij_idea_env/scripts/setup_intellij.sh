#!/bin/bash
set -e

echo "=== Setting up IntelliJ IDEA ==="

# Wait for desktop to be ready
sleep 5

# Determine IntelliJ config directory version from build.txt
# Build format: IC-243.22562.218 -> major=243 -> year=2024, minor=3
BUILD_NUM=""
if [ -f /opt/idea/build.txt ]; then
    BUILD_NUM=$(cat /opt/idea/build.txt | head -1)
    echo "IntelliJ build: $BUILD_NUM"
fi

# Parse major version from build number to get config dir name
# IC-243.x.x -> 243 -> 2024.3 (first two digits = year-20, last digit = minor)
IDEA_MAJOR=$(echo "$BUILD_NUM" | grep -oP '\d+' | head -1)
if [ -n "$IDEA_MAJOR" ] && [ "$IDEA_MAJOR" -gt 0 ] 2>/dev/null; then
    YEAR=$((IDEA_MAJOR / 10 + 2000))
    MINOR=$((IDEA_MAJOR % 10))
    IDEA_VERSION_SHORT="${YEAR}.${MINOR}"
else
    IDEA_VERSION_SHORT="2024.3"
fi
IDEA_DIR_NAME="IdeaIC${IDEA_VERSION_SHORT}"
echo "Using config directory name: $IDEA_DIR_NAME"

# Create IntelliJ config directories for user ga (suppresses first-run dialogs)
su - ga -c "mkdir -p /home/ga/.config/JetBrains/${IDEA_DIR_NAME}"
su - ga -c "mkdir -p /home/ga/.cache/JetBrains/${IDEA_DIR_NAME}"
su - ga -c "mkdir -p /home/ga/.local/share/JetBrains/${IDEA_DIR_NAME}"

# Suppress data sharing consent dialog
su - ga -c "mkdir -p /home/ga/.config/JetBrains/consentOptions"
su - ga -c "echo 'rsch.send.usage.stat:1.1:0:$(date +%s)000' > /home/ga/.config/JetBrains/consentOptions/accepted"

# Pre-accept EULA (End User Agreement) to prevent first-run dialog
# IntelliJ stores accepted EULA in a version-specific file
EULA_DIR="/home/ga/.config/JetBrains/${IDEA_DIR_NAME}"
mkdir -p "${EULA_DIR}"

# Accept the Jetbrains User Agreement (needed since 2024.x)
# This creates the "accepted" stamp file that IntelliJ checks
cat > "${EULA_DIR}/accepted" << 'EULAEOF'
jetbrains.privacy.policy.accepted=true
eua.accepted=true
EULAEOF

# Also set the privacy policy / user agreement via the newer mechanism
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

# Also try the system-level properties approach
mkdir -p "/home/ga/.config/JetBrains/${IDEA_DIR_NAME}"
cat > "${EULA_DIR}/idea.properties" << 'PROPSEOF'
idea.initially.ask.config=false
PROPSEOF

# Set custom VM options (suppress splash, increase memory, accept license)
cat > /home/ga/.config/JetBrains/${IDEA_DIR_NAME}/idea64.vmoptions << 'VMOPTS'
-Xms512m
-Xmx2048m
-XX:ReservedCodeCacheSize=512m
-Dnosplash=true
-Djb.privacy.policy.text=<!--999.999-->
-Djb.consents.confirmation.enabled=false
-Didea.initially.ask.config=false
VMOPTS
chown ga:ga /home/ga/.config/JetBrains/${IDEA_DIR_NAME}/idea64.vmoptions

# Disable tip of the day and other startup notifications
mkdir -p /home/ga/.config/JetBrains/${IDEA_DIR_NAME}/options
cat > /home/ga/.config/JetBrains/${IDEA_DIR_NAME}/options/ide.general.xml << 'IDEOPTS'
<application>
  <component name="GeneralSettings">
    <option name="showTipsOnStartup" value="false" />
    <option name="confirmExit" value="false" />
  </component>
</application>
IDEOPTS
chown ga:ga /home/ga/.config/JetBrains/${IDEA_DIR_NAME}/options/ide.general.xml

# Pre-configure trusted paths to auto-trust ~/IdeaProjects directory
# This prevents the "Trust Project" dialog from appearing
# IntelliJ 2024.x uses TrustedPathsSettings component
cat > /home/ga/.config/JetBrains/${IDEA_DIR_NAME}/options/trusted-paths.xml << 'TRUSTXML'
<application>
  <component name="TrustedPathsSettings">
    <option name="trustedPaths">
      <list>
        <option value="/home/ga/IdeaProjects" />
        <option value="/home/ga" />
        <option value="/workspace" />
        <option value="/tmp" />
      </list>
    </option>
    <option name="TRUSTED_PROJECT_PATHS">
      <map>
        <entry key="/home/ga/IdeaProjects" value="true" />
        <entry key="/home/ga" value="true" />
        <entry key="/workspace" value="true" />
      </map>
    </option>
  </component>
  <component name="Trusted.Paths.Settings">
    <option name="TRUSTED_PATHS">
      <list>
        <option value="/home/ga/IdeaProjects" />
        <option value="/home/ga" />
        <option value="/workspace" />
      </list>
    </option>
  </component>
</application>
TRUSTXML
chown ga:ga /home/ga/.config/JetBrains/${IDEA_DIR_NAME}/options/trusted-paths.xml

# Also create the trustedProjects.xml file which is used by some IntelliJ versions
cat > /home/ga/.config/JetBrains/${IDEA_DIR_NAME}/options/trustedProjects.xml << 'TRUSTEDPROJ'
<application>
  <component name="TrustedProjects">
    <option name="trustedProjects">
      <list>
        <option value="/home/ga/IdeaProjects" />
        <option value="/home/ga/IdeaProjects/gs-maven" />
        <option value="/home/ga/IdeaProjects/gs-maven-broken" />
        <option value="/home/ga/IdeaProjects/calculator" />
        <option value="/home/ga/IdeaProjects/calculator-test" />
        <option value="/home/ga/IdeaProjects/refactor-demo" />
        <option value="/workspace" />
      </list>
    </option>
  </component>
</application>
TRUSTEDPROJ
chown ga:ga /home/ga/.config/JetBrains/${IDEA_DIR_NAME}/options/trustedProjects.xml

# Configure JDK in IntelliJ
cat > /home/ga/.config/JetBrains/${IDEA_DIR_NAME}/options/jdk.table.xml << 'JDKXML'
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
chown ga:ga /home/ga/.config/JetBrains/${IDEA_DIR_NAME}/options/jdk.table.xml

# Set ownership of all JetBrains config
chown -R ga:ga /home/ga/.config/JetBrains
chown -R ga:ga /home/ga/.cache/JetBrains
chown -R ga:ga /home/ga/.local/share/JetBrains

# Create project directory
su - ga -c "mkdir -p /home/ga/IdeaProjects"

# Configure Git for ga user
su - ga -c "git config --global user.name 'ga'"
su - ga -c "git config --global user.email 'ga@localhost'"
su - ga -c "git config --global init.defaultBranch main"

# Set JAVA_HOME in ga's environment
echo 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64' >> /home/ga/.bashrc
echo 'export PATH=$JAVA_HOME/bin:$PATH' >> /home/ga/.bashrc
echo 'export IDEA_HOME=/opt/idea' >> /home/ga/.bashrc
echo 'export PATH=$IDEA_HOME/bin:$PATH' >> /home/ga/.bashrc

# Create desktop launcher
cat > /home/ga/Desktop/IntelliJ-IDEA.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=IntelliJ IDEA
Comment=IntelliJ IDEA Community Edition
Exec=/opt/idea/bin/idea.sh
Icon=/opt/idea/bin/idea.svg
StartupNotify=true
Terminal=false
Type=Application
Categories=Development;IDE;
DESKTOPEOF
chmod +x /home/ga/Desktop/IntelliJ-IDEA.desktop
chown ga:ga /home/ga/Desktop/IntelliJ-IDEA.desktop

# Launch IntelliJ IDEA (use nohup + disown to ensure it survives shell exit)
echo "Launching IntelliJ IDEA..."
su - ga -c "DISPLAY=:1 JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 nohup /opt/idea/bin/idea.sh > /tmp/intellij_startup.log 2>&1 &"
# Give a moment for the process to detach
sleep 2

# Wait for IntelliJ window to appear
echo "Waiting for IntelliJ IDEA to start..."
INTELLIJ_STARTED=false
for i in $(seq 1 90); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "intellij\|idea\|welcome"; then
        INTELLIJ_STARTED=true
        echo "IntelliJ window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$INTELLIJ_STARTED" = true ]; then
    sleep 5

    # Maximize the window
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "intellij\|idea\|welcome" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        echo "IntelliJ window maximized"
    fi

    # Dismiss any remaining startup dialogs
    sleep 3
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
else
    echo "WARNING: IntelliJ window not detected within 90 seconds"
    echo "Check /tmp/intellij_startup.log for details"
fi

echo "=== IntelliJ IDEA setup complete ==="
