#!/bin/bash
set -e

echo "=== Setting up PyCharm ==="

# Verify PyCharm was installed
if [ ! -f /opt/pycharm/bin/pycharm.sh ]; then
    echo "ERROR: PyCharm not installed at /opt/pycharm"
    echo "Contents of /opt/pycharm:"
    ls -la /opt/pycharm 2>&1 || echo "Directory does not exist"
    exit 1
fi
echo "PyCharm installation verified at /opt/pycharm"

# Wait for desktop to be ready
sleep 5

# Determine PyCharm config directory version from build.txt
# Build format: PC-243.22562.218 -> major=243 -> year=2024, minor=3
BUILD_NUM=""
if [ -f /opt/pycharm/build.txt ]; then
    BUILD_NUM=$(cat /opt/pycharm/build.txt | head -1)
    echo "PyCharm build: $BUILD_NUM"
fi

# Parse major version from build number to get config dir name
# PC-243.x.x -> 243 -> 2024.3 (first two digits = year-20, last digit = minor)
PYCHARM_MAJOR=$(echo "$BUILD_NUM" | grep -oP '\d+' | head -1)
if [ -n "$PYCHARM_MAJOR" ] && [ "$PYCHARM_MAJOR" -gt 0 ] 2>/dev/null; then
    YEAR=$((PYCHARM_MAJOR / 10 + 2000))
    MINOR=$((PYCHARM_MAJOR % 10))
    PYCHARM_VERSION_SHORT="${YEAR}.${MINOR}"
else
    PYCHARM_VERSION_SHORT="2024.3"
fi
PYCHARM_DIR_NAME="PyCharmCE${PYCHARM_VERSION_SHORT}"
echo "Using config directory name: $PYCHARM_DIR_NAME"

# Create PyCharm config directories for user ga (suppresses first-run dialogs)
su - ga -c "mkdir -p /home/ga/.config/JetBrains/${PYCHARM_DIR_NAME}"
su - ga -c "mkdir -p /home/ga/.cache/JetBrains/${PYCHARM_DIR_NAME}"
su - ga -c "mkdir -p /home/ga/.local/share/JetBrains/${PYCHARM_DIR_NAME}"

# Suppress data sharing consent dialog
su - ga -c "mkdir -p /home/ga/.config/JetBrains/consentOptions"
su - ga -c "echo 'rsch.send.usage.stat:1.1:0:$(date +%s)000' > /home/ga/.config/JetBrains/consentOptions/accepted"

# Pre-accept EULA (End User Agreement) to prevent first-run dialog
# PyCharm stores accepted EULA in a version-specific file
EULA_DIR="/home/ga/.config/JetBrains/${PYCHARM_DIR_NAME}"
mkdir -p "${EULA_DIR}"

# Accept the Jetbrains User Agreement (needed since 2024.x)
# This creates the "accepted" stamp file that PyCharm checks
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
mkdir -p "/home/ga/.config/JetBrains/${PYCHARM_DIR_NAME}"
cat > "${EULA_DIR}/pycharm.properties" << 'PROPSEOF'
idea.initially.ask.config=false
PROPSEOF

# Set custom VM options (suppress splash, increase memory, accept license)
cat > /home/ga/.config/JetBrains/${PYCHARM_DIR_NAME}/pycharm64.vmoptions << 'VMOPTS'
-Xms512m
-Xmx2048m
-XX:ReservedCodeCacheSize=512m
-Dnosplash=true
-Djb.privacy.policy.text=<!--999.999-->
-Djb.consents.confirmation.enabled=false
-Didea.initially.ask.config=false
VMOPTS
chown ga:ga /home/ga/.config/JetBrains/${PYCHARM_DIR_NAME}/pycharm64.vmoptions

# Disable tip of the day and other startup notifications
mkdir -p /home/ga/.config/JetBrains/${PYCHARM_DIR_NAME}/options
cat > /home/ga/.config/JetBrains/${PYCHARM_DIR_NAME}/options/ide.general.xml << 'IDEOPTS'
<application>
  <component name="GeneralSettings">
    <option name="showTipsOnStartup" value="false" />
    <option name="confirmExit" value="false" />
  </component>
</application>
IDEOPTS
chown ga:ga /home/ga/.config/JetBrains/${PYCHARM_DIR_NAME}/options/ide.general.xml

# Pre-configure trusted paths to auto-trust ~/PycharmProjects directory
# This prevents the "Trust Project" dialog from appearing
cat > /home/ga/.config/JetBrains/${PYCHARM_DIR_NAME}/options/trusted-paths.xml << 'TRUSTXML'
<application>
  <component name="TrustedPathsSettings">
    <option name="trustedPaths">
      <list>
        <option value="/home/ga/PycharmProjects" />
        <option value="/home/ga" />
        <option value="/workspace" />
        <option value="/tmp" />
      </list>
    </option>
    <option name="TRUSTED_PROJECT_PATHS">
      <map>
        <entry key="/home/ga/PycharmProjects" value="true" />
        <entry key="/home/ga" value="true" />
        <entry key="/workspace" value="true" />
      </map>
    </option>
  </component>
  <component name="Trusted.Paths.Settings">
    <option name="TRUSTED_PATHS">
      <list>
        <option value="/home/ga/PycharmProjects" />
        <option value="/home/ga" />
        <option value="/workspace" />
      </list>
    </option>
  </component>
</application>
TRUSTXML
chown ga:ga /home/ga/.config/JetBrains/${PYCHARM_DIR_NAME}/options/trusted-paths.xml

# Also create the trustedProjects.xml file which is used by some PyCharm versions
cat > /home/ga/.config/JetBrains/${PYCHARM_DIR_NAME}/options/trustedProjects.xml << 'TRUSTEDPROJ'
<application>
  <component name="TrustedProjects">
    <option name="trustedProjects">
      <list>
        <option value="/home/ga/PycharmProjects" />
        <option value="/workspace" />
      </list>
    </option>
  </component>
</application>
TRUSTEDPROJ
chown ga:ga /home/ga/.config/JetBrains/${PYCHARM_DIR_NAME}/options/trustedProjects.xml

# Configure default Python interpreter
cat > /home/ga/.config/JetBrains/${PYCHARM_DIR_NAME}/options/jdk.table.xml << 'JDKXML'
<application>
  <component name="ProjectJdkTable">
    <jdk version="2">
      <name value="Python 3.11" />
      <type value="Python SDK" />
      <version value="Python 3.11" />
      <homePath value="/usr/bin/python3.11" />
      <roots>
        <annotationsPath>
          <root type="composite" />
        </annotationsPath>
        <classPath>
          <root type="composite" />
        </classPath>
        <sourcePath>
          <root type="composite" />
        </sourcePath>
      </roots>
      <additional ASSOCIATED_PROJECT_PATH="" />
    </jdk>
  </component>
</application>
JDKXML
chown ga:ga /home/ga/.config/JetBrains/${PYCHARM_DIR_NAME}/options/jdk.table.xml

# Set ownership of all JetBrains config
chown -R ga:ga /home/ga/.config/JetBrains
chown -R ga:ga /home/ga/.cache/JetBrains
chown -R ga:ga /home/ga/.local/share/JetBrains

# Create project directory
su - ga -c "mkdir -p /home/ga/PycharmProjects"

# Configure Git for ga user
su - ga -c "git config --global user.name 'ga'"
su - ga -c "git config --global user.email 'ga@localhost'"
su - ga -c "git config --global init.defaultBranch main"

# Set PYCHARM_HOME in ga's environment
echo 'export PYCHARM_HOME=/opt/pycharm' >> /home/ga/.bashrc
echo 'export PATH=$PYCHARM_HOME/bin:$PATH' >> /home/ga/.bashrc

# Create desktop launcher
cat > /home/ga/Desktop/PyCharm.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=PyCharm
Comment=PyCharm Community Edition
Exec=/opt/pycharm/bin/pycharm.sh
Icon=/opt/pycharm/bin/pycharm.svg
StartupNotify=true
Terminal=false
Type=Application
Categories=Development;IDE;
DESKTOPEOF
chmod +x /home/ga/Desktop/PyCharm.desktop
chown ga:ga /home/ga/Desktop/PyCharm.desktop

# Launch PyCharm (use nohup + disown to ensure it survives shell exit)
echo "Launching PyCharm..."
su - ga -c "DISPLAY=:1 nohup /opt/pycharm/bin/pycharm.sh > /tmp/pycharm_startup.log 2>&1 &"
# Give a moment for the process to detach
sleep 2

# Wait for PyCharm window to appear
echo "Waiting for PyCharm to start..."
PYCHARM_STARTED=false
for i in $(seq 1 90); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "pycharm\|welcome"; then
        PYCHARM_STARTED=true
        echo "PyCharm window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$PYCHARM_STARTED" = true ]; then
    sleep 5

    # Maximize the window
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "pycharm\|welcome" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        echo "PyCharm window maximized"
    fi

    # Dismiss any remaining startup dialogs
    sleep 3
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
else
    echo "WARNING: PyCharm window not detected within 90 seconds"
    echo "Check /tmp/pycharm_startup.log for details"
fi

echo "=== PyCharm setup complete ==="
