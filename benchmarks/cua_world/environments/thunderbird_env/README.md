# Thunderbird Environment (`claude_thunderbird`)

A comprehensive Mozilla Thunderbird email client environment for `gym-anything`, designed for email management, calendar operations, contact management, and communication workflow tasks.

## Overview

This environment provides a complete Thunderbird email client setup with:
- **Local Folders** pre-configured for offline email testing
- **Sample emails** pre-populated for immediate testing
- **Calendar support** for event management tasks
- **Address book** for contact management
- **Comprehensive verification utilities** for email operations
- **VNC access** for visual observation and debugging
- **Full GUI automation** support via `xdotool` and `wmctrl`

## Features

### Core Capabilities

1. **Email Management**
   - Compose and send emails
   - Receive and read emails
   - Reply and forward messages
   - Manage attachments
   - Organize with folders and tags
   - Create and apply filters/rules
   - Search email content

2. **Calendar Operations**
   - Create events and appointments
   - Set reminders
   - Manage recurring events
   - View and edit calendar

3. **Contact Management**
   - Add contacts to address book
   - Edit contact information
   - Organize contacts in groups
   - Import/export contacts

4. **Verification Capabilities**
   - Parse mbox email files
   - Query SQLite address book database
   - Read calendar ICS files
   - Verify email sent/received
   - Check filters and folder structure
   - Count emails and contacts

## Directory Structure

```
claude_thunderbird/
├── env.json                              # Environment specification
├── README.md                             # This file
├── scripts/
│   ├── install_thunderbird.sh           # Thunderbird installation script
│   ├── setup_thunderbird.sh             # Thunderbird configuration script
│   └── task_utils.sh                    # Shared utility functions
├── config/
│   ├── user.js                          # Thunderbird preferences
│   └── sample_emails/                   # Pre-populated test emails
│       └── README.md
├── utils/
│   ├── __init__.py
│   └── thunderbird_verification_utils.py # Verification utilities
└── tasks/                                # Task definitions (add your tasks here)
```

## Usage

### Quick Start

```python
import gym_anything as ga

# Load the Thunderbird environment
env = ga.from_config("examples/claude_thunderbird")

# Reset the environment
obs = env.reset(seed=42)

# Environment is ready with Thunderbird launched
# Local Folders account pre-configured
# Sample emails loaded in Inbox
# VNC viewer accessible on port 5953
```

### Creating Tasks

Tasks should be placed in the `tasks/` directory. Each task needs:

1. **`task.json`**: Task specification
2. **`setup_task.sh`**: Pre-task setup script
3. **`export_result.sh`** (optional): Post-task export script
4. **`verifier.py`**: Verification logic

Example task structure:

```json
{
  "id": "compose_email@1",
  "version": "1.0",
  "env_id": "claude.thunderbird_env@0.1",
  "description": "Compose and send an email to a specific recipient",
  "init": {
    "timeout_sec": 120,
    "max_steps": 15,
    "reward_type": "sparse"
  },
  "hooks": {
    "pre_task": "/workspace/tasks/compose_email/setup_task.sh",
    "post_task": "/workspace/tasks/compose_email/export_result.sh"
  },
  "success": {
    "mode": "program",
    "spec": {
      "program": "verifier.py::verify_email_composed"
    }
  }
}
```

### Using Verification Utilities

```python
import sys
import os
# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from thunderbird_verification_utils import *

def verify_email_composed(traj, env_info, task_info):
    """Verify that an email was composed and sent"""
    copy_from_env = env_info.get('copy_from_env')

    # Set up verification by copying Sent folder
    success, files, error = setup_thunderbird_verification(
        copy_from_env,
        ["Mail/Local Folders/Sent"],
        username="ga"
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": error}

    # Verify email was sent
    sent_mbox = files.get("Sent")
    email_sent = verify_email_sent(
        sent_mbox,
        to_address="recipient@example.com",
        subject_pattern="Test Email"
    )

    # Clean up
    cleanup_verification_temp()

    return {
        "passed": email_sent,
        "score": 100 if email_sent else 0,
        "feedback": "Email sent successfully" if email_sent else "Email not found in Sent folder"
    }
```

### Using Task Utilities

```bash
#!/bin/bash
# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Thunderbird to be ready
if ! wait_for_thunderbird_ready 30; then
    echo "ERROR: Thunderbird not ready"
    exit 1
fi

# Click center of desktop to focus
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Thunderbird window
echo "Focusing Thunderbird window..."
wid=$(get_thunderbird_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Check email count
email_count=$(count_emails_in_folder "Inbox" "ga")
echo "Inbox contains $email_count emails"
```

## User Account

The environment includes one pre-configured user account:

**`ga`** (primary user)
- Full sudo access
- Home: `/home/ga`
- VNC display: `:1`
- Thunderbird profile: `/home/ga/.thunderbird/default/`
- Local Folders: `/home/ga/.thunderbird/default/Mail/Local Folders/`

## Network Ports

- **5953**: VNC server (external access)
- **SMTP/IMAP**: Not configured by default (uses Local Folders)

## Thunderbird Profile Structure

```
~/.thunderbird/
├── profiles.ini                         # Profile configuration
└── default/                             # Default profile
    ├── user.js                          # User preferences
    ├── prefs.js                         # Runtime preferences
    ├── abook.sqlite                     # Address book database
    ├── places.sqlite                    # History database
    ├── Mail/
    │   └── Local Folders/
    │       ├── Inbox                    # Inbox (mbox format)
    │       ├── Sent                     # Sent emails
    │       ├── Drafts                   # Draft emails
    │       └── Trash                    # Deleted emails
    ├── ImapMail/                        # IMAP cache (if configured)
    ├── calendar-data/                   # Calendar events (.ics files)
    └── msgFilterRules.dat               # Email filters
```

## Command-Line Utilities

### thunderbird-util

Query Thunderbird data from the command line:

```bash
# Count emails in a folder
thunderbird-util count --folder Inbox --username ga

# List all emails in a folder
thunderbird-util list --folder Sent --username ga
```

## GUI Automation

The environment includes `xdotool` and `wmctrl` for GUI automation:

```bash
# Focus Thunderbird window
wmctrl -a "Thunderbird"

# Open compose window
xdotool key ctrl+n

# Type email content
xdotool type "Hello World"

# Send email
xdotool key ctrl+Return
```

## Verification API

### Email Operations

```python
# Parse mbox file
messages = parse_mbox_file(Path("/path/to/Inbox"))

# Count emails
count = count_emails_in_mbox(Path("/path/to/Inbox"))

# Get email subjects
subjects = get_email_subjects(Path("/path/to/Inbox"))

# Find email by subject
email = get_email_by_subject(Path("/path/to/Inbox"), "Test.*")

# Verify email sent
sent = verify_email_sent(
    Path("/path/to/Sent"),
    to_address="recipient@example.com",
    subject_pattern="Test Email"
)

# Verify email received
received = verify_email_received(
    Path("/path/to/Inbox"),
    from_address="sender@example.com",
    subject_pattern="Important.*"
)
```

### Address Book Operations

```python
# Read all contacts
contacts = read_address_book(Path("/path/to/abook.sqlite"))

# Count contacts
count = get_contacts_count(Path("/path/to/abook.sqlite"))

# Verify contact exists
exists = verify_contact_exists(
    Path("/path/to/abook.sqlite"),
    email="john@example.com",
    name="John Doe"
)
```

### Calendar Operations

```python
# Get all calendar events
events = get_calendar_events(Path("/path/to/calendar-data"))

# Verify event exists
exists = verify_event_exists(
    Path("/path/to/calendar-data"),
    summary_pattern="Meeting.*"
)
```

### Other Utilities

```python
# Check if email filter exists
has_filter = check_email_filter(profile_dir, "Spam Filter")

# Get list of folders
folders = get_folder_list(profile_dir)

# Verify folder exists
exists = verify_folder_exists(profile_dir, "Work")
```

## Logs

- **Thunderbird**: `/tmp/thunderbird_ga.log`
- **Setup**: Check Docker logs or `/tmp/` directory

## Debugging

### Enable VNC Viewer
Connect to `localhost:5953` with password `password` to see the desktop.

### Check Thunderbird Status
```bash
# Inside container
ps aux | grep thunderbird
wmctrl -l | grep Thunderbird

# Check email count
thunderbird-util count --folder Inbox
```

### Verify Profile
```bash
ls -la /home/ga/.thunderbird/default/
cat /home/ga/.thunderbird/default/user.js
```

## Example Tasks

### Task Ideas

1. **Compose Email**: Write and send an email to a specific address
2. **Reply to Email**: Reply to an existing email in the inbox
3. **Create Filter**: Set up a filter to organize incoming emails
4. **Add Contact**: Add a new contact to the address book
5. **Schedule Event**: Create a calendar event
6. **Attach File**: Compose email with file attachment
7. **Search Emails**: Find emails matching search criteria
8. **Create Folder**: Create new mail folder and move emails
9. **Mark as Read/Unread**: Manage email read status
10. **Delete Spam**: Identify and delete spam emails

## Advanced Configuration

### Custom Preferences

Modify `config/user.js` to set default preferences. Changes apply to new profile setups.

### Pre-populate Emails

Add mbox files to `config/sample_emails/` to pre-populate specific test scenarios.

Example mbox format:
```
From - Mon Jan 01 00:00:00 2024
From: sender@example.com
To: recipient@example.com
Subject: Test Email
Date: Mon, 1 Jan 2024 00:00:00 +0000
Message-ID: <test@example.com>

Email body goes here.

```

### Add IMAP/SMTP Accounts

For tasks requiring real email servers, configure accounts in task setup scripts:

```bash
# Add account configuration to prefs.js
cat >> /home/ga/.thunderbird/default/prefs.js << EOF
user_pref("mail.account.account2.server", "server2");
user_pref("mail.server.server2.hostname", "imap.example.com");
user_pref("mail.server.server2.type", "imap");
user_pref("mail.server.server2.userName", "user@example.com");
EOF
```

## Troubleshooting

### Thunderbird Won't Start
- Check `/tmp/thunderbird_ga.log` for errors
- Ensure X11 display is running (`DISPLAY=:1`)
- Verify profile directory exists: `/home/ga/.thunderbird/default/`

### Emails Not Appearing
- Check mbox file exists: `/home/ga/.thunderbird/default/Mail/Local Folders/Inbox`
- Verify file permissions: `ls -la /home/ga/.thunderbird/`
- Try restarting Thunderbird

### VNC Connection Issues
- Ensure VNC server is running on port 5953
- Check password is correct: `password`
- Verify port mapping in Docker configuration

## Contributing

To add new verification utilities:

1. Add functions to `utils/thunderbird_verification_utils.py`
2. Update `utils/__init__.py` exports
3. Document in this README
4. Add example usage

## References

- [Mozilla Thunderbird](https://www.thunderbird.net/)
- [Thunderbird Profile Structure](https://support.mozilla.org/en-US/kb/profiles-where-thunderbird-stores-user-data)
- [gym-anything Documentation](../../docs/)
- [mbox Format](https://en.wikipedia.org/wiki/Mbox)

## License

This environment configuration is part of the `gym-anything` project.
