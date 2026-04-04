#!/bin/bash
set -e

echo "=== Setting up Mozilla Thunderbird ==="

# Wait for desktop to be ready
sleep 5

# ============================================================
# Create Thunderbird profile with pre-configured local account
# ============================================================

PROFILE_NAME="default-release"
PROFILE_DIR="/home/ga/.thunderbird/${PROFILE_NAME}"
LOCAL_MAIL_DIR="${PROFILE_DIR}/Mail/Local Folders"

# Create profile directory structure
mkdir -p "$PROFILE_DIR"
mkdir -p "$LOCAL_MAIL_DIR"
mkdir -p "${PROFILE_DIR}/ImapMail"

# Create profiles.ini so Thunderbird uses our profile
cat > /home/ga/.thunderbird/profiles.ini << 'EOF'
[Profile0]
Name=default-release
IsRelative=1
Path=default-release
Default=1

[General]
StartWithLastProfile=1
Version=2
EOF

# Create installs.ini to mark as non-first-run
cat > /home/ga/.thunderbird/installs.ini << 'EOF'
[E9C9B301527D4E19]
Default=default-release
Locked=1
EOF

# ============================================================
# Create user.js to suppress first-run wizard and configure
# ============================================================
cat > "${PROFILE_DIR}/user.js" << 'USERJS'
// Suppress first-run wizard and account setup
user_pref("mail.shell.checkDefaultClient", false);
user_pref("mail.shell.checkDefaultMail", false);
user_pref("mail.spotlight.firstRunDone", true);
user_pref("mail.provider.enabled", false);
user_pref("mailnews.start_page.enabled", false);
user_pref("mailnews.start_page_override.mstone", "ignore");
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);

// Disable default client check popup
user_pref("mail.shell.checkDefaultClient", false);
user_pref("mail.startup.enabledMailCheckOnce", true);

// Set up local folders account
user_pref("mail.accountmanager.accounts", "account1");
user_pref("mail.accountmanager.defaultaccount", "account1");
user_pref("mail.accountmanager.localfoldersserver", "server1");
user_pref("mail.account.account1.server", "server1");
user_pref("mail.account.account1.identities", "id1");

// Local folders server config (type "none" = local only)
user_pref("mail.server.server1.type", "none");
user_pref("mail.server.server1.name", "Local Folders");
user_pref("mail.server.server1.hostname", "Local Folders");
user_pref("mail.server.server1.storeContractID", "@mozilla.org/msgstore/berkeleystore;1");
user_pref("mail.server.server1.directory-rel", "[ProfD]Mail/Local Folders");
user_pref("mail.server.server1.userName", "ga");

// Identity configuration (for composing emails)
user_pref("mail.identity.id1.fullName", "Test User");
user_pref("mail.identity.id1.useremail", "testuser@example.com");
user_pref("mail.identity.id1.valid", true);
user_pref("mail.identity.id1.smtpServer", "");
user_pref("mail.identity.id1.compose_html", true);
user_pref("mail.identity.id1.drafts_folder_picker_mode", "0");
user_pref("mail.identity.id1.draft_folder", "mailbox://ga@Local%20Folders/Drafts");
user_pref("mail.identity.id1.fcc_folder_picker_mode", "0");
user_pref("mail.identity.id1.fcc_folder", "mailbox://ga@Local%20Folders/Sent");

// Disable auto-check for new messages
user_pref("mail.server.default.check_new_mail", false);
user_pref("mail.server.server1.check_new_mail", false);

// Performance and UI settings
user_pref("mail.pane_config.dynamic", 0);
user_pref("mailnews.message_display.disable_remote_image", false);
user_pref("mail.compose.max_recycled_windows", 0);

// Disable crash reporter and update nag
user_pref("breakpad.reportURL", "");
user_pref("toolkit.crashreporter.enabled", false);
USERJS

# ============================================================
# Import real emails from SpamAssassin public corpus into
# Thunderbird's local folders (mbox format)
# ============================================================

echo "Importing email data into local folders..."

# Create standard folder structure
mkdir -p "$LOCAL_MAIL_DIR"

# Create Inbox mbox file from ham emails
INBOX_MBOX="${LOCAL_MAIL_DIR}/Inbox"
> "$INBOX_MBOX"

# Import ham emails (these are real emails from SpamAssassin corpus)
EMAIL_COUNT=0
if [ -d "/workspace/assets/emails/ham" ]; then
    for eml_file in /workspace/assets/emails/ham/*; do
        if [ -f "$eml_file" ] && [ $EMAIL_COUNT -lt 50 ]; then
            # mbox format: each message starts with "From " line
            SENDER=$(grep -m1 "^From:" "$eml_file" 2>/dev/null | sed 's/From: //' | head -1 || echo "sender@example.com")
            DATE=$(grep -m1 "^Date:" "$eml_file" 2>/dev/null | sed 's/Date: //' | head -1 || echo "Mon Jan 01 00:00:00 2024")

            # Write mbox separator
            echo "From ${SENDER} ${DATE}" >> "$INBOX_MBOX"
            # Write the email content
            cat "$eml_file" >> "$INBOX_MBOX"
            echo "" >> "$INBOX_MBOX"

            EMAIL_COUNT=$((EMAIL_COUNT + 1))
        fi
    done
    echo "Imported $EMAIL_COUNT ham emails into Inbox"
else
    echo "WARNING: No ham email assets found at /workspace/assets/emails/ham"
fi

# Create Junk mbox file from spam emails
JUNK_MBOX="${LOCAL_MAIL_DIR}/Junk"
> "$JUNK_MBOX"

SPAM_COUNT=0
if [ -d "/workspace/assets/emails/spam" ]; then
    for eml_file in /workspace/assets/emails/spam/*; do
        if [ -f "$eml_file" ] && [ $SPAM_COUNT -lt 20 ]; then
            SENDER=$(grep -m1 "^From:" "$eml_file" 2>/dev/null | sed 's/From: //' | head -1 || echo "spammer@example.com")
            DATE=$(grep -m1 "^Date:" "$eml_file" 2>/dev/null | sed 's/Date: //' | head -1 || echo "Mon Jan 01 00:00:00 2024")

            echo "From ${SENDER} ${DATE}" >> "$JUNK_MBOX"
            cat "$eml_file" >> "$JUNK_MBOX"
            echo "" >> "$JUNK_MBOX"

            SPAM_COUNT=$((SPAM_COUNT + 1))
        fi
    done
    echo "Imported $SPAM_COUNT spam emails into Junk"
fi

# Create empty Drafts, Sent, Trash folders
touch "${LOCAL_MAIL_DIR}/Drafts"
touch "${LOCAL_MAIL_DIR}/Sent"
touch "${LOCAL_MAIL_DIR}/Trash"
touch "${LOCAL_MAIL_DIR}/Templates"

# Create .msf (index) files will be auto-generated by Thunderbird on first run
# Set ownership
chown -R ga:ga /home/ga/.thunderbird

# ============================================================
# Create desktop launcher
# ============================================================
cat > /home/ga/Desktop/thunderbird.desktop << 'DESKTOP'
[Desktop Entry]
Name=Mozilla Thunderbird
Comment=Email Client
Exec=thunderbird -profile /home/ga/.thunderbird/default-release
Icon=thunderbird
StartupNotify=true
Terminal=false
Type=Application
Categories=Network;Email;
DESKTOP
chown ga:ga /home/ga/Desktop/thunderbird.desktop
chmod +x /home/ga/Desktop/thunderbird.desktop

# Create launch script
cat > /home/ga/launch_thunderbird.sh << 'LAUNCH'
#!/bin/bash
export DISPLAY=${DISPLAY:-:1}
xhost +local: 2>/dev/null || true

# Launch Thunderbird with pre-configured profile
thunderbird -profile /home/ga/.thunderbird/default-release > /tmp/thunderbird_ga.log 2>&1 &

echo "Thunderbird started"
echo "Log file: /tmp/thunderbird_ga.log"
LAUNCH
chown ga:ga /home/ga/launch_thunderbird.sh
chmod +x /home/ga/launch_thunderbird.sh

echo "=== Mozilla Thunderbird setup complete ==="
echo "Profile: $PROFILE_DIR"
echo "Inbox emails: $EMAIL_COUNT"
echo "Junk emails: $SPAM_COUNT"
echo "Local folders: Inbox, Junk, Drafts, Sent, Trash, Templates"
