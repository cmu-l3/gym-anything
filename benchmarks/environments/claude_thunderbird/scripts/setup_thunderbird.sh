#!/bin/bash
set -euo pipefail

echo "=== Setting up Thunderbird configuration ==="

# Set up Thunderbird for a specific user
setup_user_thunderbird() {
    local username=$1
    local home_dir=$2

    echo "Setting up Thunderbird for user: $username"

    # Ensure user exists and home directory is accessible
    if ! id "$username" &>/dev/null; then
        echo "ERROR: User $username does not exist"
        return 1
    fi

    # Ensure home directory exists with correct permissions
    if [ ! -d "$home_dir" ]; then
        mkdir -p "$home_dir"
        chown $username:$username "$home_dir"
    fi

    # Create Thunderbird profile directory structure
    local tb_dir="$home_dir/.thunderbird"
    local profile_name="default"
    local profile_dir="$tb_dir/$profile_name"

    echo "  - Creating profile directory: $profile_dir"

    # Create all directories as the user
    sudo -u $username mkdir -p "$profile_dir"
    sudo -u $username mkdir -p "$profile_dir/Mail/Local Folders"
    sudo -u $username mkdir -p "$profile_dir/ImapMail"
    sudo -u $username mkdir -p "$profile_dir/calendar-data"
    sudo -u $username mkdir -p "$home_dir/Documents"
    sudo -u $username mkdir -p "$home_dir/Desktop"

    # Create profiles.ini to define the default profile
    # IMPORTANT: Must be created as the user with correct permissions
    sudo -u $username tee "$tb_dir/profiles.ini" > /dev/null << PROFILESEOF
[General]
StartWithLastProfile=1
Version=2

[Profile0]
Name=default
IsRelative=1
Path=$profile_name
Default=1
PROFILESEOF
    echo "  - Created profiles.ini"

    # Verify profiles.ini was created correctly
    if [ ! -f "$tb_dir/profiles.ini" ]; then
        echo "ERROR: Failed to create profiles.ini"
        return 1
    fi

    # Copy custom preferences if available, otherwise create default
    if [ -f "/workspace/config/user.js" ]; then
        sudo -u $username cp "/workspace/config/user.js" "$profile_dir/"
        echo "  - Copied custom user.js preferences"
    else
        # Create default preferences optimized for container/agent use
        sudo -u $username tee "$profile_dir/user.js" > /dev/null << 'PREFSEOF'
// Thunderbird preferences for gym-anything environment
// Optimized for container usage and agent interaction

// === Disable First-Run and Updates ===
user_pref("mail.provider.enabled", false);
user_pref("mail.startup.enabledMailCheckOnce", false);
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("extensions.update.enabled", false);

// === Disable Telemetry and Reporting ===
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.archive.enabled", false);

// === Mail Settings ===
user_pref("mail.shell.checkDefaultClient", false);
user_pref("mail.root.none-rel", "[ProfD]Mail");
user_pref("mail.root.none", "Mail");
user_pref("mail.server.default.check_new_mail", false);
user_pref("mail.startup.enabledMailCheckOnce", false);

// === Compose Settings ===
user_pref("mail.compose.default_to_paragraph", false);
user_pref("mail.compose.attachment_reminder", false);
user_pref("mail.SpellCheckBeforeSend", false);
user_pref("mail.warn_on_send_accel_key", false);

// === Performance ===
user_pref("mail.db.global.indexer.enabled", true);
user_pref("mailnews.database.global.indexer.enabled", true);
user_pref("mail.strictly_mime", false);

// === UI Settings ===
user_pref("mail.tabs.autoHide", false);
user_pref("mail.tabs.drawInTitlebar", false);
user_pref("browser.tabs.warnOnClose", false);

// === Offline/Network ===
user_pref("offline.autoDetect", false);
user_pref("offline.startup_state", 0);

// === Calendar ===
user_pref("calendar.timezone.local", "America/New_York");
user_pref("calendar.alarms.show", false);

// === Privacy ===
user_pref("mail.collect_email_address_outgoing", false);
user_pref("mailnews.message_display.disable_remote_image", false);

// === Debugging ===
user_pref("devtools.debugger.remote-enabled", true);
user_pref("devtools.chrome.enabled", true);
PREFSEOF
        echo "  - Created default user.js preferences"
    fi

    # Create Local Folders account configuration
    sudo -u $username tee "$profile_dir/prefs.js" > /dev/null << 'MAINPREFSEOF'
// Main Thunderbird preferences - auto-generated
user_pref("mail.account.account1.identities", "id1");
user_pref("mail.account.account1.server", "server1");
user_pref("mail.accountmanager.accounts", "account1");
user_pref("mail.accountmanager.defaultaccount", "account1");
user_pref("mail.accountmanager.localfoldersserver", "server1");
user_pref("mail.identity.id1.fullName", "Test User");
user_pref("mail.identity.id1.useremail", "test@localhost");
user_pref("mail.identity.id1.valid", true);
user_pref("mail.server.server1.directory-rel", "[ProfD]Mail/Local Folders");
user_pref("mail.server.server1.hostname", "Local Folders");
user_pref("mail.server.server1.name", "Local Folders");
user_pref("mail.server.server1.type", "none");
user_pref("mail.server.server1.userName", "nobody");
MAINPREFSEOF
    echo "  - Created Local Folders account"

    # Pre-populate sample emails if available
    if [ -d "/workspace/config/sample_emails" ]; then
        sudo -u $username cp -r "/workspace/config/sample_emails/"* "$profile_dir/Mail/Local Folders/" 2>/dev/null || true
        echo "  - Copied sample emails"
    else
        # Create a simple test inbox with sample emails
        sudo -u $username tee "$profile_dir/Mail/Local Folders/Inbox" > /dev/null << 'INBOXEOF'
From - Mon Jan 01 00:00:00 2024
From: sender@example.com
To: test@localhost
Subject: Welcome to Thunderbird
Date: Mon, 1 Jan 2024 00:00:00 +0000
Message-ID: <welcome@example.com>

Welcome to Thunderbird! This is a sample email for testing.

From - Mon Jan 01 00:01:00 2024
From: info@example.com
To: test@localhost
Subject: Test Email 2
Date: Mon, 1 Jan 2024 00:01:00 +0000
Message-ID: <test2@example.com>

This is another test email for verification purposes.

INBOXEOF

        # Create empty folders
        sudo -u $username touch "$profile_dir/Mail/Local Folders/Sent"
        sudo -u $username touch "$profile_dir/Mail/Local Folders/Drafts"
        sudo -u $username touch "$profile_dir/Mail/Local Folders/Trash"
        echo "  - Created sample inbox with test emails"
    fi

    # Ensure all files have correct permissions
    chown -R $username:$username "$tb_dir"
    echo "  - Set correct permissions on profile directory"

    # Set up desktop shortcut
    sudo -u $username tee "$home_dir/Desktop/Thunderbird.desktop" > /dev/null << DESKTOPEOF
[Desktop Entry]
Name=Thunderbird Mail
Comment=Email and Calendar Client
Exec=$home_dir/launch_thunderbird.sh %u
Icon=thunderbird
StartupNotify=true
Terminal=false
Type=Application
Categories=Network;Email;Calendar;
MimeType=message/rfc822;x-scheme-handler/mailto;application/x-extension-eml;
DESKTOPEOF
    chmod +x "$home_dir/Desktop/Thunderbird.desktop"
    echo "  - Created desktop shortcut"

    # Create launch script
    sudo -u $username tee "$home_dir/launch_thunderbird.sh" > /dev/null << 'LAUNCHEOF'
#!/bin/bash
# Launch Thunderbird with optimized settings for container environment
# IMPORTANT: This must run as non-root user (Thunderbird refuses to run as root)

# Check we're not running as root
if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR: Thunderbird cannot run as root. Please run as normal user."
    exit 1
fi

export DISPLAY=${DISPLAY:-:1}

# Ensure proper permissions for X11
xhost +local: 2>/dev/null || true

# Set Thunderbird environment variables
export MOZ_DISABLE_CONTENT_SANDBOX=1
export MOZ_DISABLE_GMP_SANDBOX=1

# Ensure profile directory exists
if [ ! -d "$HOME/.thunderbird" ]; then
    echo "ERROR: Thunderbird profile directory not found: $HOME/.thunderbird"
    exit 1
fi

# Launch Thunderbird
echo "Launching Thunderbird as user: $(whoami)"
thunderbird "$@" > /tmp/thunderbird_$USER.log 2>&1 &

echo "Thunderbird started"
echo "Log file: /tmp/thunderbird_$USER.log"
LAUNCHEOF
    chmod +x "$home_dir/launch_thunderbird.sh"
    echo "  - Created launch script"
}

# Setup for ga user (the main VNC user)
if id "ga" &>/dev/null; then
    setup_user_thunderbird "ga" "/home/ga"
else
    echo "WARNING: User 'ga' not found, skipping Thunderbird setup"
fi

# Create utility scripts for mail operations
cat > /usr/local/bin/thunderbird-util << 'TBUTILEOF'
#!/usr/bin/env python3
"""
Thunderbird utility for common mail operations and verification
Provides helper functions to interact with Thunderbird data
"""
import sys
import os
import mailbox
import email
import argparse
import json
from pathlib import Path

def get_profile_dir(username="ga"):
    """Get the Thunderbird profile directory"""
    home = Path(f"/home/{username}")
    tb_dir = home / ".thunderbird"

    if not tb_dir.exists():
        return None

    # Find the default profile
    for item in tb_dir.iterdir():
        if item.is_dir() and not item.name.startswith('.'):
            return item
    return None

def count_emails(folder="Inbox", username="ga"):
    """Count emails in a folder"""
    profile_dir = get_profile_dir(username)
    if not profile_dir:
        return 0

    mbox_path = profile_dir / "Mail" / "Local Folders" / folder
    if not mbox_path.exists():
        return 0

    try:
        mbox = mailbox.mbox(str(mbox_path))
        return len(mbox)
    except Exception as e:
        print(f"Error counting emails: {e}", file=sys.stderr)
        return 0

def list_emails(folder="Inbox", username="ga"):
    """List emails in a folder"""
    profile_dir = get_profile_dir(username)
    if not profile_dir:
        return []

    mbox_path = profile_dir / "Mail" / "Local Folders" / folder
    if not mbox_path.exists():
        return []

    emails = []
    try:
        mbox = mailbox.mbox(str(mbox_path))
        for idx, message in enumerate(mbox):
            emails.append({
                'index': idx,
                'from': message.get('From', ''),
                'to': message.get('To', ''),
                'subject': message.get('Subject', ''),
                'date': message.get('Date', ''),
                'message_id': message.get('Message-ID', '')
            })
    except Exception as e:
        print(f"Error listing emails: {e}", file=sys.stderr)

    return emails

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Thunderbird Utility')
    parser.add_argument('command', choices=['count', 'list'])
    parser.add_argument('--folder', default='Inbox')
    parser.add_argument('--username', default='ga')
    args = parser.parse_args()

    if args.command == 'count':
        count = count_emails(args.folder, args.username)
        print(count)
    elif args.command == 'list':
        emails = list_emails(args.folder, args.username)
        print(json.dumps(emails, indent=2))
TBUTILEOF
chmod +x /usr/local/bin/thunderbird-util

echo "=== Thunderbird configuration completed ==="

# Launch Thunderbird for the main VNC user (to speed up first access)
# IMPORTANT: Must run as ga user, NOT root
echo "Starting Thunderbird for ga user..."
if id "ga" &>/dev/null; then
    # Run as ga user using su
    su - ga -c "/home/ga/launch_thunderbird.sh" || {
        echo "WARNING: Failed to launch Thunderbird"
        echo "Check /tmp/thunderbird_ga.log for details"
    }
    sleep 3
else
    echo "WARNING: User 'ga' not found, skipping auto-launch"
fi

echo "Thunderbird is ready! Users can:"
echo "  - Launch from desktop shortcut"
echo "  - Run 'thunderbird' from terminal AS NON-ROOT USER"
echo "  - Run '~/launch_thunderbird.sh' for optimized launch"
echo "  - Use 'thunderbird-util' for mail queries"
echo "  - Local Folders account pre-configured"
echo "  - Sample emails loaded in Inbox"
echo ""
echo "IMPORTANT: Thunderbird CANNOT run as root!"
echo "  Always run as: su - ga -c 'thunderbird'"
