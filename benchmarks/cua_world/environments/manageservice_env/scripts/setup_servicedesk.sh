#!/bin/bash
# ManageEngine ServiceDesk Plus Setup Script (post_start hook)
#
# Runs after desktop starts. Configures Firefox profile only.
# Returns quickly (<60s). Does NOT wait for SDP install (too slow).
#
# The pre_task hook in each task (setup_task.sh) calls ensure_sdp_running
# from task_utils.sh, which waits for install and starts SDP (up to 3600s).
#
# SDP Credentials: administrator / administrator
# SDP Web UI: https://localhost:8080/ManageEngine/Login.do

echo "=== ManageEngine ServiceDesk Plus Post-Start ==="

# =====================================================
# Configure Firefox snap profile
# =====================================================
echo "Configuring Firefox snap profile..."

FIREFOX_PROFILE_BASE="/home/ga/snap/firefox/common/.mozilla/firefox"
mkdir -p "$FIREFOX_PROFILE_BASE/sdp.profile"

cat > "$FIREFOX_PROFILE_BASE/profiles.ini" << 'FFPROFILE'
[Install4F96D1932A9F858E]
Default=sdp.profile
Locked=1

[Profile0]
Name=sdp-profile
IsRelative=1
Path=sdp.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
FFPROFILE

cat > "$FIREFOX_PROFILE_BASE/sdp.profile/user.js" << 'USERJS'
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
user_pref("browser.startup.homepage", "https://localhost:8080/ManageEngine/Login.do");
user_pref("browser.startup.page", 1);
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("security.insecure_field_warning.contextual.enabled", false);
USERJS

chown -R ga:ga "$FIREFOX_PROFILE_BASE"
echo "Firefox profile configured."

# =====================================================
# Desktop shortcut
# =====================================================
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/ServiceDeskPlus.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=ManageEngine ServiceDesk Plus
Comment=ITSM Helpdesk Software
Exec=firefox https://localhost:8080/ManageEngine/Login.do
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Network;Office;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/ServiceDeskPlus.desktop
chmod +x /home/ga/Desktop/ServiceDeskPlus.desktop

echo "=== Post-Start Done ==="
echo "Note: SDP install runs in background. pre_task hooks will wait for it."
