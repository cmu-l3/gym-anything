#!/bin/bash
set -e

echo "=== Setting up Anaconda Navigator ==="

# Verify Anaconda was installed
if [ ! -f /home/ga/anaconda3/bin/conda ]; then
    echo "ERROR: Anaconda not installed at /home/ga/anaconda3"
    exit 1
fi
echo "Anaconda installation verified"

# Wait for desktop to be ready
sleep 5

# Hide GNOME dock to prevent it from intercepting clicks on Navigator sidebar
# The dock overlaps with Navigator's left sidebar (Environments, Learning, Community tabs)
# Must run as ga user since gsettings/dconf need the user's dbus session
su - ga -c "DISPLAY=:1 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u)/bus dconf write /org/gnome/shell/extensions/dash-to-dock/dock-fixed false" 2>/dev/null || true
su - ga -c "DISPLAY=:1 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u)/bus gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false" 2>/dev/null || true
su - ga -c "DISPLAY=:1 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u)/bus gsettings set org.gnome.shell.extensions.dash-to-dock autohide true" 2>/dev/null || true
su - ga -c "DISPLAY=:1 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u)/bus gsettings set org.gnome.shell.extensions.dash-to-dock intellihide true" 2>/dev/null || true
sleep 2

# Ensure conda is initialized for ga
su - ga -c "source /home/ga/anaconda3/etc/profile.d/conda.sh && conda activate base && conda --version"

# Configure Firefox profile for Jupyter (disable first-run dialogs)
mkdir -p /home/ga/.mozilla/firefox/default.profile
cat > /home/ga/.mozilla/firefox/default.profile/user.js << 'EOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.startup.firstrunSkipsHomepage", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("browser.newtabpage.activity-stream.feeds.topsites", false);
user_pref("browser.newtabpage.activity-stream.showSearch", false);
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
EOF

cat > /home/ga/.mozilla/firefox/profiles.ini << 'EOF'
[Profile0]
Name=default
IsRelative=1
Path=default.profile
Default=1

[General]
StartWithLastProfile=1
EOF
chown -R ga:ga /home/ga/.mozilla

# Create a working directory for notebooks
mkdir -p /home/ga/notebooks
chown ga:ga /home/ga/notebooks

# Create desktop launcher for Anaconda Navigator
cat > /home/ga/Desktop/AnacondaNavigator.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Anaconda Navigator
Comment=Anaconda Navigator - GUI for conda
Exec=/home/ga/anaconda3/bin/anaconda-navigator
Icon=/home/ga/anaconda3/lib/python3.12/site-packages/anaconda_navigator/static/images/anaconda-icon-256x256.png
StartupNotify=true
Terminal=false
Type=Application
Categories=Development;Science;
DESKTOPEOF
chmod +x /home/ga/Desktop/AnacondaNavigator.desktop
chown ga:ga /home/ga/Desktop/AnacondaNavigator.desktop

# Set environment variables in .bashrc
cat >> /home/ga/.bashrc << 'BASHEOF'
export ANACONDA_HOME=/home/ga/anaconda3
export PATH=$ANACONDA_HOME/bin:$PATH
BASHEOF
chown ga:ga /home/ga/.bashrc

# NOTE: Navigator is NOT launched here. Each task's pre_task hook launches
# Navigator with the correct GA_NAV_DEFAULT_TAB env var to set the initial tab.
# This is necessary because:
# 1. Navigator's sidebar uses Qt Quick/QML rendering which does NOT respond to
#    programmatic mouse clicks (pyautogui, xdotool, XTest, evdev)
# 2. The only reliable way to set the tab is via GA_NAV_DEFAULT_TAB at launch time
# 3. Launching per-task avoids GNOME focus-stealing (first window gets focus)
echo "Navigator will be launched by task setup scripts with the correct default tab"

echo "=== Anaconda Navigator setup complete ==="
