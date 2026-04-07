#!/bin/bash
set -e

echo "=== Setting up Eclipse IDE ==="

# Wait for desktop to be ready
sleep 5

# Create Eclipse workspace directory
su - ga -c "mkdir -p /home/ga/eclipse-workspace"

# Create Eclipse config directories (suppresses first-run dialogs)
su - ga -c "mkdir -p /home/ga/.eclipse"

# Pre-configure Eclipse workspace settings to disable welcome screen and tips
WORKSPACE_SETTINGS="/home/ga/eclipse-workspace/.metadata/.plugins/org.eclipse.core.runtime/.settings"
mkdir -p "$WORKSPACE_SETTINGS"

# Disable welcome screen on startup
cat > "$WORKSPACE_SETTINGS/org.eclipse.ui.prefs" << 'PREFS'
eclipse.preferences.version=1
showIntro=false
quickAccessDialogLocationX=1225
quickAccessDialogLocationY=97
quickAccessDialogTextEntry=
PREFS

# Disable tip of the day
cat > "$WORKSPACE_SETTINGS/org.eclipse.tips.ide.prefs" << 'PREFS'
eclipse.preferences.version=1
dailyTipOnStartup=false
PREFS

# Configure general workspace preferences
cat > "$WORKSPACE_SETTINGS/org.eclipse.ui.ide.prefs" << 'PREFS'
eclipse.preferences.version=1
EXIT_PROMPT_ON_CLOSE_LAST_WINDOW=false
RECENT_WORKSPACES=/home/ga/eclipse-workspace
SHOW_RECENT_WORKSPACES=false
SHOW_WORKSPACE_SELECTION_DIALOG=false
WORKSPACE_FIRST_USE_DIALOG_VERSION_EPOCH=-1
WORKSPACE_NAME=eclipse-workspace
PREFS

# Configure JDK in Eclipse preferences
cat > "$WORKSPACE_SETTINGS/org.eclipse.jdt.launching.prefs" << 'PREFS'
eclipse.preferences.version=1
org.eclipse.jdt.launching.PREF_VM_XML=<?xml version\="1.0" encoding\="UTF-8" standalone\="no"?>\n<vmSettings defaultVM\="57,org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType13,1728000000000">\n<vmType id\="org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType">\n<vm id\="1728000000000" javadocURL\="" name\="java-17-openjdk-amd64" path\="/usr/lib/jvm/java-17-openjdk-amd64"/>\n</vmType>\n</vmSettings>
PREFS

# Configure JDT Core preferences (compiler settings)
cat > "$WORKSPACE_SETTINGS/org.eclipse.jdt.core.prefs" << 'PREFS'
eclipse.preferences.version=1
org.eclipse.jdt.core.compiler.codegen.inlineJsrBytecode=enabled
org.eclipse.jdt.core.compiler.codegen.targetPlatform=17
org.eclipse.jdt.core.compiler.compliance=17
org.eclipse.jdt.core.compiler.problem.assertIdentifier=error
org.eclipse.jdt.core.compiler.problem.enablePreviewFeatures=disabled
org.eclipse.jdt.core.compiler.problem.enumIdentifier=error
org.eclipse.jdt.core.compiler.release=enabled
org.eclipse.jdt.core.compiler.source=17
PREFS

# Set ownership of all settings
chown -R ga:ga /home/ga/eclipse-workspace
chown -R ga:ga /home/ga/.eclipse

# Configure Git for ga user
su - ga -c "git config --global user.name 'ga'"
su - ga -c "git config --global user.email 'ga@localhost'"
su - ga -c "git config --global init.defaultBranch main"

# Set JAVA_HOME in ga's environment
echo 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64' >> /home/ga/.bashrc
echo 'export PATH=$JAVA_HOME/bin:$PATH' >> /home/ga/.bashrc
echo 'export ECLIPSE_HOME=/opt/eclipse' >> /home/ga/.bashrc
echo 'export PATH=$ECLIPSE_HOME:$PATH' >> /home/ga/.bashrc

# Create desktop launcher
cat > /home/ga/Desktop/Eclipse.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Eclipse IDE
Comment=Eclipse IDE for Java Developers
Exec=/opt/eclipse/eclipse -data /home/ga/eclipse-workspace
Icon=/opt/eclipse/icon.xpm
StartupNotify=true
Terminal=false
Type=Application
Categories=Development;IDE;
DESKTOPEOF
chmod +x /home/ga/Desktop/Eclipse.desktop
chown ga:ga /home/ga/Desktop/Eclipse.desktop
# Mark desktop file as trusted (GNOME requirement)
su - ga -c "dbus-launch gio set /home/ga/Desktop/Eclipse.desktop metadata::trusted true" 2>/dev/null || true

# Suppress Firefox first-run dialogs and Privacy Notice page
# Firefox may be launched by Eclipse or by the desktop environment
echo "Configuring Firefox to suppress first-run pages..."
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox"
mkdir -p "$FIREFOX_PROFILE_DIR"

# Create profiles.ini with a default profile
cat > "$FIREFOX_PROFILE_DIR/profiles.ini" << 'PROFILESEOF'
[General]
StartWithLastProfile=1

[Profile0]
Name=default-release
IsRelative=1
Path=default-release
Default=1
PROFILESEOF

# Create the default profile directory
mkdir -p "$FIREFOX_PROFILE_DIR/default-release"

# Create user.js with prefs to suppress all first-run behavior
cat > "$FIREFOX_PROFILE_DIR/default-release/user.js" << 'USERJS'
// Suppress first-run pages and privacy notice
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("startup.homepage_welcome_url", "");
user_pref("startup.homepage_welcome_url.additional", "");
user_pref("startup.homepage_override_url", "");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("trailhead.firstrun.didSeeAboutWelcome", true);
user_pref("browser.rights.3.shown", true);
user_pref("browser.startup.firstrunSkipsHomepage", true);
user_pref("datareporting.policy.dataSubmissionPolicyAcceptedVersion", 2);
user_pref("toolkit.telemetry.enabled", false);
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
USERJS

chown -R ga:ga "$FIREFOX_PROFILE_DIR"

# Also set system-wide Firefox autoconfig to suppress first-run for all profiles
FIREFOX_DIR=$(find /usr/lib /usr/lib64 /snap -maxdepth 3 -name "firefox" -type d 2>/dev/null | head -1)
if [ -n "$FIREFOX_DIR" ] && [ -d "$FIREFOX_DIR" ]; then
    mkdir -p "$FIREFOX_DIR/defaults/pref"
    cat > "$FIREFOX_DIR/defaults/pref/autoconfig.js" << 'AUTOCONFIGJS'
pref("general.config.filename", "mozilla.cfg");
pref("general.config.obscure_value", 0);
AUTOCONFIGJS
    cat > "$FIREFOX_DIR/mozilla.cfg" << 'MOZILLACFG'
// Skip first-run
defaultPref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
defaultPref("toolkit.telemetry.reportingpolicy.firstRun", false);
defaultPref("browser.aboutwelcome.enabled", false);
MOZILLACFG
fi

# Launch Eclipse (use nohup + disown to ensure it survives shell exit)
echo "Launching Eclipse IDE..."
su - ga -c "DISPLAY=:1 JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 nohup /opt/eclipse/eclipse -data /home/ga/eclipse-workspace -nosplash > /tmp/eclipse_startup.log 2>&1 &"
# Give a moment for the process to detach
sleep 2

# Wait for Eclipse window to appear
echo "Waiting for Eclipse IDE to start..."
ECLIPSE_STARTED=false
for i in $(seq 1 120); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "eclipse\|java\|workspace"; then
        ECLIPSE_STARTED=true
        echo "Eclipse window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$ECLIPSE_STARTED" = true ]; then
    sleep 5

    # Maximize the window
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "eclipse\|java\|workspace" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        echo "Eclipse window maximized"
    fi

    # Dismiss any remaining startup dialogs (welcome screen, tips)
    sleep 3
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true

    # Close welcome tab if present (Ctrl+W)
    sleep 2
    DISPLAY=:1 xdotool key ctrl+w 2>/dev/null || true

    # Kill any Firefox that may have launched (first-run page)
    pkill -f firefox 2>/dev/null || true
    sleep 1

    # Re-focus Eclipse window after killing Firefox
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "eclipse\|java\|workspace" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
else
    echo "WARNING: Eclipse window not detected within 120 seconds"
    echo "Check /tmp/eclipse_startup.log for details"
fi

echo "=== Eclipse IDE setup complete ==="
